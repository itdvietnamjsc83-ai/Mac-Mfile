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

# Phông: biểu tượng Fluent (MIT) đóng kèm. Muốn có Selawik (OFL) thì chép selawk*.ttf vào Resources/Fonts.
mkdir -p "$APP/Contents/Resources/Fonts"
cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"
ls "$APP/Contents/Resources/Fonts"

# Ký ad-hoc để macOS chạy được bản thử (chưa phải chữ ký Developer ID).
codesign --force --deep --sign - "$APP"

( cd "$OUT" && ditto -c -k --keepParent "Mac Mfile.app" "MacMfile-$VERSION.zip" )
hdiutil create -volname "Mac Mfile" -srcfolder "$APP" -ov -format UDZO "$OUT/MacMfile-$VERSION.dmg" >/dev/null

echo "Đã tạo: $OUT/MacMfile-$VERSION.zip và $OUT/MacMfile-$VERSION.dmg"
