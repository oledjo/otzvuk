#!/usr/bin/env python3
"""Рисует иконку приложения: расходящиеся круги-отзвуки на спокойном фоне."""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("RGB", (S, S))
px = img.load()
top, bottom = (36, 92, 96), (20, 52, 62)
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
    for x in range(S):
        px[x, y] = c

layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)
cx, cy = S // 2, S // 2
for i, (r, a) in enumerate([(120, 255), (230, 150), (340, 85), (450, 45)]):
    w = 36 if i else 0
    if i == 0:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(235, 247, 245, a))
    else:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(235, 247, 245, a), width=w)
layer = layer.filter(ImageFilter.GaussianBlur(1.2))
img = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Otzvuk", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")
img.save(out)
print(out)
