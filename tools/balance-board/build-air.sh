#!/bin/zsh
# Copy boardbridge.m to the 2011 MacBook Air (ssh host "oldair") and compile it there with its
# Xcode 7.2. The toolchain's clang is called directly: /usr/bin/clang stops at the unaccepted
# Xcode license, which only an admin can accept.
set -e
cd "${0:A:h}"
ssh oldair 'mkdir -p ~/boardbridge'
scp -q boardbridge.m oldair:boardbridge/
ssh oldair 'cd ~/boardbridge && D=/Applications/Xcode.app/Contents/Developer &&
  $D/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -isysroot $D/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.11.sdk \
    -mmacosx-version-min=10.11 -fobjc-arc -O2 -framework Foundation -framework IOBluetooth -framework IOKit -o boardbridge boardbridge.m &&
  echo built ~/boardbridge/boardbridge on the Air'
