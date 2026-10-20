#!/bin/zsh
# The 26.5 SDK: the Command Line Tools swiftc (6.3) is older than their default 27.0 SDK.
# Build BoardTest.app next to this script and sign it ad hoc (so macOS remembers the Bluetooth permission).
set -e
cd "${0:A:h}"
rm -rf BoardTest.app
mkdir -p BoardTest.app/Contents/MacOS
cp Info.plist BoardTest.app/Contents/
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -O -framework IOBluetooth -o BoardTest.app/Contents/MacOS/BoardTest BoardTest.swift
codesign --force -s - BoardTest.app
echo built BoardTest.app
