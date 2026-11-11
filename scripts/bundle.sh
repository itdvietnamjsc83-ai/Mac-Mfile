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

# Phông: biểu tượng Fluent (MIT) đóng kèm sẵn; Selawik (OFL, thay cho Segoe UI) tải lúc build nếu được, lỗi thì bỏ qua.
mkdir -p "$APP/Contents/Resources/Fonts"
cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"
# Kho Selawik chỉ có mã nguồn; bản .ttf nằm ở mục Releases.
SEL="$(mktemp -d)"
ASSET="$(curl -fsSL https://api.github.com/repos/microsoft/Selawik/releases/latest 2>/dev/null \
  | grep -oE '"browser_download_url": *"[^"]+\.zip"' | head -1 | sed -E 's/.*"(https[^"]+)"/\1/' || true)"
echo "Selawik: ${ASSET:-không tìm thấy bản phát hành}"
if [ -n "$ASSET" ] && curl -fsSL "$ASSET" -o "$SEL/s.zip" && unzip -q "$SEL/s.zip" -d "$SEL/s"; then
  find "$SEL/s" -iname '*.ttf' -exec cp {} "$APP/Contents/Resources/Fonts/" \; || true
  find "$SEL/s" -iname 'LICENSE*' -exec cp {} "$APP/Contents/Resources/Fonts/Selawik-LICENSE.txt" \; || true
fi
ls "$APP/Contents/Resources/Fonts"

# Ký ad-hoc để macOS chạy được bản thử (chưa phải chữ ký Developer ID).
codesign --force --deep --sign - "$APP"

( cd "$OUT" && ditto -c -k --keepParent "Mac Mfile.app" "MacMfile-$VERSION.zip" )
hdiutil create -volname "Mac Mfile" -srcfolder "$APP" -ov -format UDZO "$OUT/MacMfile-$VERSION.dmg" >/dev/null

echo "Đã tạo: $OUT/MacMfile-$VERSION.zip và $OUT/MacMfile-$VERSION.dmg"
