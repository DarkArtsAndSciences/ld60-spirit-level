// BoardTest: connect to a Wii Balance Board over Bluetooth without the Wii, and log its
// four weight sensors.
//
// macOS can't pair Nintendo controllers (their PIN is raw bytes, the host's Bluetooth
// address reversed), so this does what the Dolphin emulator does: find the board while
// its red sync button is pressed, and open the two HID channels directly, unpaired.
// Protocol: https://wiibrew.org/wiki/Wii_Balance_Board and https://wiibrew.org/wiki/Wiimote
//
// Runs as an app bundle (BoardTest.app) so macOS can ask for Bluetooth permission.
// Writes to board.log next to the app; `tail -f` it.

import Foundation
import IOBluetooth

let logURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("board.log")
FileManager.default.createFile(atPath: logURL.path, contents: nil)
let logHandle = try! FileHandle(forWritingTo: logURL)

func log(_ s: String) {
    let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withTime, .withColonSeparatorInTime])
    logHandle.write("\(stamp) \(s)\n".data(using: .utf8)!)
}

final class Board: NSObject, IOBluetoothDeviceInquiryDelegate, IOBluetoothL2CAPChannelDelegate {
    var inquiry: IOBluetoothDeviceInquiry!
    var device: IOBluetoothDevice?
    var control: IOBluetoothL2CAPChannel?
    var interrupt: IOBluetoothL2CAPChannel?

    // Calibration: raw readings at 0, 17 and 34 kg for each sensor, in report order
    // (top right, bottom right, top left, bottom left).
    var calBytes: [UInt8] = []
    var cal: [[Double]]? = nil
    var lastPrint = Date.distantPast

    func start() {
        inquiry = IOBluetoothDeviceInquiry(delegate: self)
        inquiry.updateNewDeviceNames = true
        inquiry.inquiryLength = 8
        log("Looking for the board. Press the red sync button in its battery compartment.")
        inquiry.start()
    }

    // MARK: finding it

    // Connecting while the inquiry is still running times out (the radio is busy), so a found
    // board waits here until the inquiry has really stopped.
    var pending: IOBluetoothDevice?

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        let name = device.name ?? "(no name)"
        guard pending == nil, name.contains("RVL-WBC") || name.contains("Nintendo") else { return }
        log("Found \(name) \(device.addressString ?? "")")
        pending = device
        sender.stop()
    }

    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        deviceInquiryDeviceFound(sender, device: device)
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        if let found = pending {
            pending = nil
            connect(found)
        } else if device == nil {
            sender.start()                    // nothing yet: keep looking
        }
    }

    // MARK: connecting

    func connect(_ dev: IOBluetoothDevice) {
        guard device == nil else { return }
        device = dev
        // The baseband link first, without authentication: there is no pairing to check.
        // Page timeout is in 0.625 ms slots; 0x4000 is about 10 s.
        var r = dev.openConnection(nil, withPageTimeout: 0x4000, authenticationRequired: false)
        log("Link: \(r == kIOReturnSuccess ? "open" : "failed \(r)")")
        var ch: IOBluetoothL2CAPChannel? = nil
        r = dev.openL2CAPChannelSync(&ch, withPSM: 0x11, delegate: self)       // HID control
        log("Control channel: \(r == kIOReturnSuccess ? "open" : "failed \(r)")")
        control = ch
        ch = nil
        r = dev.openL2CAPChannelSync(&ch, withPSM: 0x13, delegate: self)       // HID interrupt
        log("Interrupt channel: \(r == kIOReturnSuccess ? "open" : "failed \(r)")")
        interrupt = ch
        guard control != nil, interrupt != nil else {
            log("Couldn't open both channels. Press sync and try again.")
            control?.close(); interrupt?.close(); dev.closeConnection()
            control = nil; interrupt = nil
            device = nil
            inquiry.start()
            return
        }
        setUp()
    }

    func send(_ bytes: [UInt8]) {
        var b: [UInt8] = [0xA2] + bytes                 // 0xA2: an output report
        let r = b.withUnsafeMutableBytes { interrupt?.writeSync($0.baseAddress, length: UInt16($0.count)) }
        if r != kIOReturnSuccess { log("write failed \(String(describing: r))") }
        usleep(30_000)
    }

    func writeRegister(_ address: UInt32, _ value: UInt8) {
        var report: [UInt8] = [0x16, 0x04, UInt8(address >> 16 & 0xFF), UInt8(address >> 8 & 0xFF), UInt8(address & 0xFF), 0x01, value]
        report += [UInt8](repeating: 0, count: 22 - report.count)  // 16 data bytes
        send(report)
    }

    func setUp() {
        send([0x11, 0x10])                    // LED 1 on: "connected"
        writeRegister(0xA400F0, 0x55)          // initialise the extension (the board) ...
        writeRegister(0xA400FB, 0x00)          // ... with encryption off
        send([0x17, 0x04, 0xA4, 0x00, 0x24, 0x00, 0x18])   // read 24 calibration bytes
        setMode()
    }

    func setMode() {
        send([0x12, 0x04, 0x32])              // continuous reports: buttons + 8 extension bytes
    }

    // MARK: reading it

    func l2capChannelData(_ channel: IOBluetoothL2CAPChannel!, data: UnsafeMutableRawPointer!, length: Int) {
        let d = [UInt8](UnsafeRawBufferPointer(start: data, count: length))
        guard d.count >= 2, d[0] == 0xA1 else { return }   // 0xA1: an input report
        switch d[1] {
        case 0x20:                                        // status: the board resets the mode
            log("Status report: battery \(d.count > 7 ? Int(d[7]) : -1)/200ish")
            setMode()
        case 0x21:                                        // memory read reply
            guard d.count >= 23 else { return }
            let size = Int(d[4] >> 4) + 1
            if d[4] & 0x0F != 0 { log("calibration read error \(d[4] & 0x0F)"); return }
            calBytes += d[7..<(7 + size)]
            if calBytes.count >= 24 { finishCalibration() }
        case 0x32:
            guard d.count >= 12 else { return }
            reading(Array(d[4..<12]))
        default:
            break
        }
    }

    func finishCalibration() {
        let v = stride(from: 0, to: 24, by: 2).map { Double(UInt16(calBytes[$0]) << 8 | UInt16(calBytes[$0 + 1])) }
        cal = (0..<4).map { [v[$0], v[$0 + 4], v[$0 + 8]] }   // per sensor: 0, 17, 34 kg
        log("Calibration (TR, BR, TL, BL at 0/17/34 kg): \(cal!.map { $0.map { Int($0) } })")
    }

    func kg(_ raw: Double, _ c: [Double]) -> Double {
        if raw < c[1] { return 17 * (raw - c[0]) / (c[1] - c[0]) }
        return 17 + 17 * (raw - c[1]) / (c[2] - c[1])
    }

    func reading(_ e: [UInt8]) {
        guard Date().timeIntervalSince(lastPrint) > 0.2 else { return }   // 5 lines a second
        lastPrint = Date()
        let raw = stride(from: 0, to: 8, by: 2).map { Double(UInt16(e[$0]) << 8 | UInt16(e[$0 + 1])) }
        guard let cal else { log("raw \(raw.map { Int($0) }) (no calibration yet)"); return }
        let w = (0..<4).map { max(0, kg(raw[$0], cal[$0])) }
        let (tr, br, tl, bl) = (w[0], w[1], w[2], w[3])
        let total = tr + br + tl + bl
        // centre of balance, -1 to 1: x is left/right, y is toes/heels
        let x = total > 2 ? ((tr + br) - (tl + bl)) / total : 0
        let y = total > 2 ? ((tl + tr) - (bl + br)) / total : 0
        log(String(format: "TR %5.1f  BR %5.1f  TL %5.1f  BL %5.1f  total %5.1f kg   x %+.2f  y %+.2f", tr, br, tl, bl, total, x, y))
    }

    func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel!) {
        log("Channel closed (the board turned off or went out of range).")
        device = nil; control = nil; interrupt = nil; calBytes = []; cal = nil
        inquiry.start()
    }
}

let board = Board()
board.start()
RunLoop.main.run()
