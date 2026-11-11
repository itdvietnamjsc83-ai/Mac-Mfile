# Mac Mfile

Trình quản lý tệp cho macOS có bố cục, phím tắt và cách thao tác giống Windows 11 File Explorer, giao diện song ngữ Việt – Anh.

- Kế hoạch: https://claude.ai/artifact/5m2e3Z7nDkWPinjHGGgM4o
- Bản mẫu giao diện đã duyệt (Cổng 1, 11/11/2026): https://claude.ai/artifact/7NLmMbs4arKYfZBvaDs22h

## Tải bản chạy thử

Mỗi lần có thay đổi, GitHub Actions tự build trên máy macOS. Vào tab **Actions** › lần chạy mới nhất › mục **Artifacts** để tải `MacMfile-….dmg`.

Bản thử chưa có chữ ký Developer ID, nên lần đầu mở: nhấp chuột phải vào **Mac Mfile** › **Mở** › **Mở**.

## Build trên máy

Cần macOS 14 trở lên và Xcode 16 (hoặc Command Line Tools có Swift 6).

```sh
swift test             # kiểm thử phần lõi
swift run MacMfile     # chạy thử
scripts/bundle.sh      # đóng gói build/Mac Mfile.app, .zip, .dmg
```

## Cấu trúc

| Thư mục | Nội dung |
| --- | --- |
| `Sources/MfileCore` | Phần lõi không phụ thuộc AppKit: chuỗi Việt – Anh, định dạng dung lượng và ngày, phân tích đường dẫn dán vào, sắp xếp tên tiếng Việt, lịch sử điều hướng |
| `Sources/MacMfile` | Ứng dụng AppKit: cửa sổ kiểu Windows 11, thanh lệnh, ngăn điều hướng, chế độ Chi tiết, thanh trạng thái, phím tắt |
| `Tests/MfileCoreTests` | Kiểm thử phần lõi |
| `scripts/bundle.sh` | Đóng gói thành `.app`, `.zip`, `.dmg` |
