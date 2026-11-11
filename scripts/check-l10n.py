#!/usr/bin/env python3
"""Báo khóa trùng trong bảng chữ L10n (khóa trùng làm ứng dụng sập khi mở)."""
import re, sys, collections, pathlib
s = pathlib.Path(__file__).resolve().parent.parent.joinpath("Sources/MfileCore/L10n.swift").read_text()
keys = re.findall(r'^\s+"([^"]+)":\s*\(', s, re.M)
dup = [k for k, c in collections.Counter(keys).items() if c > 1]
if dup:
    print("Khóa trùng:", ", ".join(dup)); sys.exit(1)
print(f"{len(keys)} khóa, không trùng")
