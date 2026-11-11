#!/usr/bin/env bash
# Đóng gói bản build thành Mac Mfile.app và tệp .zip, .dmg để tải về chạy thử.
# Dùng: scripts/bundle.sh [phiên bản] [số build]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
BUILD="${2:-1}"
OUT="build"
APP="$OUT/Mac Mfile.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacMfile"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacMfile"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Phông và biểu tượng đóng kèm: Fluent System Icons, Fluent Emoji (MIT), Open Sans (OFL).
mkdir -p "$APP/Contents/Resources/Fonts"
cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"
mkdir -p "$APP/Contents/Resources/Icons"
cp Resources/Icons/* "$APP/Contents/Resources/Icons/"
ls "$APP/Contents/Resources/Fonts"

# Ký ad-hoc để macOS chạy được bản thử (chưa phải chữ ký Developer ID).
codesign --force --deep --sign - "$APP"

( cd "$OUT" && ditto -c -k --keepParent "Mac Mfile.app" "MacMfile-$VERSION.zip" )
# Đĩa .dmg kiểu cài đặt kéo-thả: có sẵn lối tắt tới thư mục Applications.
DMGSRC="$(mktemp -d)"
cp -R "$APP" "$DMGSRC/"
ln -s /Applications "$DMGSRC/Applications"
hdiutil create -volname "Mac Mfile" -srcfolder "$DMGSRC" -ov -format UDZO "$OUT/MacMfile-$VERSION.dmg" >/dev/null

# Bộ cài .pkg: bấm vào là mở Trình cài đặt của macOS, cài app vào /Applications.
PKGROOT="$(mktemp -d)"
mkdir -p "$PKGROOT/Applications"
cp -R "$APP" "$PKGROOT/Applications/"
# Không cho Trình cài đặt "dời" app sang chỗ có bản cũ: luôn cài vào /Applications.
pkgbuild --analyze --root "$PKGROOT" "$OUT/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$OUT/component.plist"
pkgbuild --root "$PKGROOT" --component-plist "$OUT/component.plist" --identifier vn.macmfile.app --version "$VERSION" \
  --install-location / "$OUT/MacMfile-component.pkg" >/dev/null
cat > "$OUT/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>Mac Mfile $VERSION</title>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
  <choices-outline><line choice="app"/></choices-outline>
  <choice id="app" visible="false"><pkg-ref id="vn.macmfile.app"/></choice>
  <pkg-ref id="vn.macmfile.app" version="$VERSION" onConclusion="none">MacMfile-component.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$OUT/distribution.xml" --package-path "$OUT" "$OUT/MacMfile-$VERSION.pkg" >/dev/null
rm -f "$OUT/MacMfile-component.pkg" "$OUT/distribution.xml" "$OUT/component.plist"
pkgutil --payload-files "$OUT/MacMfile-$VERSION.pkg" | grep -m1 "Applications/Mac Mfile.app" >/dev/null

echo "Đã tạo: $OUT/MacMfile-$VERSION.pkg, .dmg và .zip"
