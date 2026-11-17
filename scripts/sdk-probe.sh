#!/usr/bin/env bash
# P1 probe (IOS_SPEC §4.4): confirm the toolchain and that iPhone Duo APIs exist in the SDK
# before any code uses them. Read-only; prints FOUND / MISSING per symbol.
set -uo pipefail
echo "== toolchain"; xcodebuild -version || true
echo "sdk(iphonesimulator)=$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || echo none)"
swift --version 2>/dev/null | head -1 || true
echo "== installed Xcodes"; ls -d /Applications/Xcode*.app 2>/dev/null || true
echo "== simulator device types (Duo)"; xcrun simctl list devicetypes 2>/dev/null | grep -i -E "duo|fold" || echo "no Duo device type"
echo "== runtimes"; xcrun simctl list runtimes 2>/dev/null | grep -i ios || true
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
if [ -z "$SDK" ]; then echo "no SDK"; exit 0; fi
echo "== symbols in $SDK"
for sym in reservedRegions ReservedRegion UIViewReservedRegion ArrangementView arrangementViewStyle overlayArrangementZIndex UIArrangementViewController onHingeChange UIHingeInteraction defaultTabBarPlacement ConcentricRectangle UICornerConfiguration BGAppRefreshTask ASWebAuthenticationSession; do
  hit=$(grep -rIl --include='*.swiftinterface' --include='*.h' "$sym" "$SDK/System/Library/Frameworks" 2>/dev/null | head -3 | sed "s#$SDK/System/Library/Frameworks/##" | tr '\n' ' ')
  if [ -n "$hit" ]; then echo "FOUND   $sym  ($hit)"; else echo "MISSING $sym"; fi
done
