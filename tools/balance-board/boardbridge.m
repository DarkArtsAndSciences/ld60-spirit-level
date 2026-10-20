// boardbridge: read a Wii Balance Board on an older Mac and print one line per reading.
//
// For the 2011 MacBook Air (OS X 10.11). macOS 12 and later can't connect to the board at all
// (they run a service query first, which it fails: see BoardTest.swift). OS X 10.11 can, and
// then its own HID driver attaches to the board, as it would to any Bluetooth input device.
//
// Two ways in, tried in this order:
//   1. Let OS X own the link. Bring the connection up, wait for the board to appear as a HID
//      device (Nintendo, vendor 0x057E, product 0x0306), and talk to it with IOHIDDevice
//      reports. No race with the system's driver.
//   2. If it hasn't appeared after a few seconds, open the two L2CAP channels ourselves, the
//      way the Dolphin emulator did. This worked once on 2026-10-16 but usually loses a race
//      with the HID driver for the interrupt channel ("not open" 0xe00002cd, or writes refused
//      with "not privileged" 0xe00002c1); the Air's system.log shows the driver competing.
//
// Output on stdout, one line per reading (about 30 a second), so it can be piped anywhere:
//   board <TR> <BR> <TL> <BL> <total> <x> <y>     kilograms, then centre of balance -1..1
//   info <text>                                  everything else
// `boardbridge off` releases the board and turns the Air's Bluetooth off.
// Protocol: https://wiibrew.org/wiki/Wii_Balance_Board and https://wiibrew.org/wiki/Wiimote
//
// Build (on the newer Mac, for the Air): see build-air.sh

#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
#import <IOKit/hid/IOHIDManager.h>

static void say(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    printf("%s\n", s.UTF8String);
    fflush(stdout);
}

@interface Board : NSObject <IOBluetoothDeviceInquiryDelegate, IOBluetoothL2CAPChannelDelegate>
@property IOBluetoothDeviceInquiry *inquiry;
@property IOBluetoothDevice *device, *pending;
@property IOBluetoothL2CAPChannel *control, *interrupt;   // route 2 only
- (void)hidAppeared:(IOHIDDeviceRef)hid;
- (void)hidGone:(IOHIDDeviceRef)hid;
- (void)report:(const uint8_t *)r length:(size_t)n;       // r[0] is the report ID
@end

static void hidMatched(void *ctx, IOReturn result, void *sender, IOHIDDeviceRef hid) {
    [(__bridge Board *)ctx hidAppeared:hid];
}
static void hidRemoved(void *ctx, IOReturn result, void *sender, IOHIDDeviceRef hid) {
    [(__bridge Board *)ctx hidGone:hid];
}
static void hidInput(void *ctx, IOReturn result, void *sender, IOHIDReportType type,
                     uint32_t reportID, uint8_t *report, CFIndex length) {
    Board *board = (__bridge Board *)ctx;
    if (length > 0 && report[0] == reportID) {
        [board report:report length:length];
    } else {                                                // the ID wasn't included: add it
        uint8_t buf[64] = {(uint8_t)reportID};
        CFIndex n = MIN(length, (CFIndex)sizeof buf - 1);
        memcpy(buf + 1, report, n);
        [board report:buf length:n + 1];
    }
}

@implementation Board {
    IOHIDManagerRef manager;
    IOHIDDeviceRef hid;
    uint8_t inputBuffer[64];
    uint8_t calBytes[24];
    int calCount;
    double cal[4][3];     // per sensor (TR, BR, TL, BL): raw at 0, 17, 34 kg
    BOOL calibrated;
    BOOL buttonWasDown;
    int setupAttempts;
    NSTimeInterval lastLine;
}

- (void)start {
    manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)@{
        @kIOHIDVendorIDKey: @0x057E, @kIOHIDProductIDKey: @0x0306});
    IOHIDManagerRegisterDeviceMatchingCallback(manager, hidMatched, (__bridge void *)self);
    IOHIDManagerRegisterDeviceRemovalCallback(manager, hidRemoved, (__bridge void *)self);
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);

    self.inquiry = [IOBluetoothDeviceInquiry inquiryWithDelegate:self];
    self.inquiry.updateNewDeviceNames = YES;
    self.inquiry.inquiryLength = 8;
    say(@"info looking for the board: press the red sync button in its battery compartment");
    [self.inquiry start];
}

// finding it

- (void)deviceInquiryDeviceFound:(IOBluetoothDeviceInquiry *)sender device:(IOBluetoothDevice *)dev {
    NSString *name = dev.name ?: @"";
    if (self.pending || self.device || hid) return;
    if (![name containsString:@"RVL-WBC"] && ![name containsString:@"Nintendo"]) return;
    say(@"info found %@ %@", name, dev.addressString);
    self.pending = dev;
    [sender stop];   // connect once the inquiry has really stopped: the radio can't do both
}

- (void)deviceInquiryDeviceNameUpdated:(IOBluetoothDeviceInquiry *)sender device:(IOBluetoothDevice *)dev devicesRemaining:(uint32_t)n {
    [self deviceInquiryDeviceFound:sender device:dev];
}

- (void)deviceInquiryComplete:(IOBluetoothDeviceInquiry *)sender error:(IOReturn)error aborted:(BOOL)aborted {
    if (self.pending) {
        IOBluetoothDevice *d = self.pending;
        self.pending = nil;
        [self connect:d];
    } else if (!self.device && !hid) {
        [sender start];
    }
}

// connecting, route 1: bring the link up and let OS X attach its HID driver

- (void)connect:(IOBluetoothDevice *)dev {
    self.device = dev;
    IOReturn r = [dev openConnection];
    say(@"info link %@; waiting for OS X to attach it as an input device",
        r == kIOReturnSuccess ? @"up" : [NSString stringWithFormat:@"failed 0x%x", r]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self->hid || self.device != dev) return;
        say(@"info no input device after 6 s; opening the channels directly");
        [self openChannels:dev];
    });
}

- (void)hidAppeared:(IOHIDDeviceRef)device {
    if (hid) return;
    hid = device;
    CFRetain(hid);
    setupAttempts = 0;
    say(@"info the board is attached as an input device; using it");
    IOHIDDeviceRegisterInputReportCallback(hid, inputBuffer, sizeof inputBuffer, hidInput, (__bridge void *)self);
    [self setUp];
}

- (void)hidGone:(IOHIDDeviceRef)device {
    if (device != hid) return;
    CFRelease(hid);
    hid = NULL;
    say(@"info disconnected (board off or out of range); looking again");
    [self reset];
}

// connecting, route 2: the channels ourselves

- (void)openChannels:(IOBluetoothDevice *)dev {
    IOBluetoothL2CAPChannel *ch = nil;
    IOReturn r = [self open:dev psm:kBluetoothL2CAPPSMHIDControl into:&ch];
    say(@"info control channel %@", r == kIOReturnSuccess ? @"open" : [NSString stringWithFormat:@"failed 0x%x", r]);
    self.control = ch; ch = nil;
    r = [self open:dev psm:kBluetoothL2CAPPSMHIDInterrupt into:&ch];
    say(@"info interrupt channel %@", r == kIOReturnSuccess ? @"open" : [NSString stringWithFormat:@"failed 0x%x", r]);
    self.interrupt = ch;
    if (!self.control || !self.interrupt) {
        say(@"info could not open both channels; press sync again");
        [self reset];
        return;
    }
    usleep(300000);
    [self setUp];
}

// One channel, up to three tries.
- (IOReturn)open:(IOBluetoothDevice *)dev psm:(BluetoothL2CAPPSM)psm into:(IOBluetoothL2CAPChannel **)ch {
    IOReturn r = kIOReturnError;
    for (int attempt = 0; attempt < 3; attempt++) {
        *ch = nil;
        r = [dev openL2CAPChannelSync:ch withPSM:psm delegate:self];
        if (r == kIOReturnSuccess) return r;
        usleep(400000);
    }
    return r;
}

- (void)l2capChannelData:(IOBluetoothL2CAPChannel *)channel data:(void *)ptr length:(size_t)n {
    const uint8_t *d = ptr;
    if (n >= 2 && d[0] == 0xA1) [self report:d + 1 length:n - 1];     // 0xA1: an input report
}

- (void)l2capChannelClosed:(IOBluetoothL2CAPChannel *)channel {
    if (!self.device || hid) return;
    say(@"info disconnected (board off or out of range); looking again");
    [self reset];
}

// Close whatever is open, wait for the radio to let go, and search again.
- (void)reset {
    IOBluetoothDevice *dev = self.device;
    self.device = nil;                       // first, so the close callbacks stay quiet
    [self.control closeChannel]; [self.interrupt closeChannel];
    self.control = self.interrupt = nil;
    if (!hid) [dev closeConnection];
    calCount = 0; calibrated = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!self->hid && !self.device) [self.inquiry start];
    });
}

// talking to it (either route)

// bytes[0] is the report ID.
- (BOOL)send:(const uint8_t *)bytes length:(int)n {
    IOReturn r;
    if (hid) {
        r = IOHIDDeviceSetReport(hid, kIOHIDReportTypeOutput, bytes[0], bytes, n);
        if (r != kIOReturnSuccess)          // some drivers want the data without the ID byte
            r = IOHIDDeviceSetReport(hid, kIOHIDReportTypeOutput, bytes[0], bytes + 1, n - 1);
    } else {
        uint8_t buf[32] = {0xA2};           // an output report on the interrupt channel
        memcpy(buf + 1, bytes, n);
        r = [self.interrupt writeSync:buf length:(UInt16)(n + 1)];
    }
    if (r != kIOReturnSuccess) say(@"info write failed 0x%x", r);
    usleep(30000);
    return r == kIOReturnSuccess;
}

- (void)write:(uint32_t)address value:(uint8_t)v {
    uint8_t b[22] = {0x16, 0x04, (address >> 16) & 0xFF, (address >> 8) & 0xFF, address & 0xFF, 0x01, v};
    [self send:b length:22];                                            // always 16 data bytes
}

- (void)setUp {
    calCount = 0; calibrated = NO;
    if (![self send:(uint8_t[]){0x11, 0x10} length:2]) {               // LED 1: connected
        say(@"info the board refused the setup; resetting, press sync again");
        if (hid) { IOHIDDeviceRegisterInputReportCallback(hid, inputBuffer, sizeof inputBuffer, NULL, NULL); CFRelease(hid); hid = NULL; }
        [self reset];
        return;
    }
    [self write:0xA400F0 value:0x55];                                   // initialise the board
    [self write:0xA400FB value:0x00];                                   // ... unencrypted
    [self send:(uint8_t[]){0x17, 0x04, 0xA4, 0x00, 0x24, 0x00, 0x18} length:7];  // read calibration
    [self setMode];
    // OS X can hand us the device a few seconds before its driver has finished starting
    // (blued logs "addDeviceToHIDEmulationMode" ~7 s after the link comes up); setup sent
    // in that gap is accepted and silently lost. So: no calibration within 2 s, send it again.
    int attempt = ++setupAttempts;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self->calibrated || !self->hid || attempt != self->setupAttempts) return;
        if (attempt >= 8) { say(@"info the board never answered; press its power button and sync again"); return; }
        say(@"info no answer from the board yet; sending the setup again");
        [self setUp];
    });
}

- (void)setMode {
    [self send:(uint8_t[]){0x12, 0x04, 0x32} length:3];                // continuous: buttons + 8 bytes
}

// reading it

- (void)report:(const uint8_t *)r length:(size_t)n {
    switch (r[0]) {
    case 0x20:                                                          // status: mode resets
        say(@"info status: battery %d", n > 6 ? r[6] : -1);
        [self setMode];
        break;
    case 0x21: {                                                        // memory read reply
        if (n < 22) return;
        if (r[3] & 0x0F) { say(@"info calibration read error %d", r[3] & 0x0F); return; }
        int size = (r[3] >> 4) + 1;
        for (int i = 0; i < size && calCount < 24; i++) calBytes[calCount++] = r[6 + i];
        if (calCount >= 24 && !calibrated) [self finishCalibration];
        break;
    }
    case 0x32:
        if (n >= 11) {
            [self powerButton:(r[2] & 0x08) != 0];     // the board's one button reports as A
            [self reading:r + 3];
        }
        break;
    }
}

// While connected, the board's power button is only a button: the board turns itself off
// when the host drops the link. So a press here drops it.
- (void)powerButton:(BOOL)down {
    if (down && !buttonWasDown && self.device) {
        say(@"info power button pressed: disconnecting, so the board turns off");
        [self.device closeConnection];
    }
    buttonWasDown = down;
}

- (void)finishCalibration {
    for (int point = 0; point < 3; point++)
        for (int s = 0; s < 4; s++) {
            int i = point * 8 + s * 2;
            cal[s][point] = (calBytes[i] << 8) | calBytes[i + 1];
        }
    calibrated = YES;
    say(@"info calibration TR %.0f/%.0f/%.0f BR %.0f/%.0f/%.0f TL %.0f/%.0f/%.0f BL %.0f/%.0f/%.0f",
        cal[0][0], cal[0][1], cal[0][2], cal[1][0], cal[1][1], cal[1][2],
        cal[2][0], cal[2][1], cal[2][2], cal[3][0], cal[3][1], cal[3][2]);
}

static double kg(double raw, const double c[3]) {
    double v = raw < c[1] ? 17 * (raw - c[0]) / (c[1] - c[0]) : 17 + 17 * (raw - c[1]) / (c[2] - c[1]);
    return v < 0 ? 0 : v;
}

- (void)reading:(const uint8_t *)e {
    if (!calibrated) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - lastLine < 1.0 / 30) return;                             // 30 lines a second
    lastLine = now;
    double w[4];
    for (int s = 0; s < 4; s++) w[s] = kg((e[s * 2] << 8) | e[s * 2 + 1], cal[s]);
    double tr = w[0], br = w[1], tl = w[2], bl = w[3], total = tr + br + tl + bl;
    double x = total > 2 ? ((tr + br) - (tl + bl)) / total : 0;          // right is +
    double y = total > 2 ? ((tl + tr) - (bl + br)) / total : 0;          // toes are +
    say(@"board %.2f %.2f %.2f %.2f %.2f %+.3f %+.3f", tr, br, tl, bl, total, x, y);
}
@end

// Private but long-stable IOBluetooth calls (the ones the blueutil tool uses), so the
// radio can be switched on without a trip to the menu bar.
extern int IOBluetoothPreferenceGetControllerPowerState(void);
extern void IOBluetoothPreferenceSetControllerPowerState(int state);

// `boardbridge off`: let go of any connected board (it then turns itself off) and switch the
// Air's Bluetooth off again, which is how it was before all this.
static int off(void) {
    NSMutableArray *known = [NSMutableArray array];
    [known addObjectsFromArray:[IOBluetoothDevice pairedDevices] ?: @[]];
    [known addObjectsFromArray:[IOBluetoothDevice recentDevices:0] ?: @[]];
    for (IOBluetoothDevice *d in known)
        if ([d.name containsString:@"RVL-"] && d.isConnected) {
            [d closeConnection];
            say(@"info disconnected %@", d.name);
        }
    sleep(1);
    IOBluetoothPreferenceSetControllerPowerState(0);
    say(@"info Bluetooth off");
    return 0;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "off") == 0) return off();
        if (!IOBluetoothPreferenceGetControllerPowerState()) {
            say(@"info Bluetooth was off; turning it on");
            IOBluetoothPreferenceSetControllerPowerState(1);
            for (int i = 0; i < 50 && !IOBluetoothPreferenceGetControllerPowerState(); i++) usleep(100000);
            sleep(2);
        }
        Board *board = [Board new];
        [board start];
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
