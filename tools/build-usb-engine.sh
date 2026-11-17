#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-build/USBDisplayEngine}"
mkdir -p "$(dirname "$output")"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
# Explicit source list excludes Sparkle, Android, receiver, discovery and upstream UI.
xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macosx14.0 -sdk "$sdk" \
  -import-objc-header Mac/OpenSidecarMac-Bridging-Header.h \
  Mac/OpenSidecarMacApp.swift Mac/MacSender.swift Mac/Usbmux.swift Mac/InputInjector.swift \
  Mac/VirtualDisplay.swift Mac/VirtualCanvasSizing.swift Mac/StreamConfiguration.swift \
  Mac/PhoneInfo.swift Mac/DesktopPolicy.swift Mac/OriginRestore.swift Mac/CaptureSourceCheck.swift \
  Mac/TestPatternWindow.swift Mac/DisplayArrangement.swift Mac/Log.swift Mac/LogPolicies.swift \
  Shared/Protocol.swift Shared/AppStore.swift Shared/DirectCable.swift \
  -o "$output"
