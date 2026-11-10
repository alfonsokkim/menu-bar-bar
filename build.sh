#!/bin/zsh
set -euo pipefail
root="${0:A:h}"
swift build --package-path "$root" -c release
binary="$(swift build --package-path "$root" -c release --show-bin-path)/Tray"
app="$root/dist/Menu Bar Bar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Tray"
cp "$root/Assets/MenuBarBar.icns" "$app/Contents/Resources/MenuBarBar.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Menu Bar Bar</string>
<key>CFBundleDisplayName</key><string>Menu Bar Bar</string>
<key>CFBundleIdentifier</key><string>com.alfonsokim.tray</string>
<key>CFBundleExecutable</key><string>Tray</string>
<key>CFBundleIconFile</key><string>MenuBarBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.4</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccessibilityUsageDescription</key><string>Menu Bar Bar opens the original menu of the menu bar item you click.</string>
<key>NSScreenCaptureUsageDescription</key><string>Menu Bar Bar displays the real icons you bundle and the wallpaper behind the shelf. Images remain on this Mac.</string>
</dict></plist>
PLIST
# Ad-hoc signing works without an Apple developer account.
# Set MENUBARBAR_SIGN_IDENTITY to use your own certificate instead.
codesign --force --options runtime --sign "${MENUBARBAR_SIGN_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
print "$app"
