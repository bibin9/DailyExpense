"""Generates the Daily Expense Tracker launcher icons (BCR). Requires Pillow.
Run from the repo root: python tool/icon/make_icons.py"""
import os
from PIL import Image, ImageDraw, ImageFont

BLUE, DARK, WHITE = (21, 101, 192), (13, 71, 161), (255, 255, 255)
S = 1024

def font(size):
    for f in ("C:/Windows/Fonts/arialbd.ttf", "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()

img = Image.new("RGB", (S, S), BLUE)
d = ImageDraw.Draw(img)
# Receipt body with zig-zag bottom edge.
l, t, r, b = 262, 170, 762, 840
d.rounded_rectangle([l, t, r, b], radius=48, fill=WHITE)
teeth, w = 8, (r - l) / 8
pts = [(l, b - 10)]
for i in range(teeth):
    pts += [(l + i * w + w / 2, b + 52), (l + (i + 1) * w, b - 10)]
d.polygon(pts + [(r, b - 60), (l, b - 60)], fill=WHITE)
# Text and lines.
f = font(150)
tw = d.textlength("AED", font=f)
d.text(((S - tw) / 2, 250), "AED", font=f, fill=DARK)
for y, x2 in ((480, 690), (560, 640), (640, 690)):
    d.rounded_rectangle([334, y, x2, y + 34], radius=17, fill=(187, 222, 251))
d.rounded_rectangle([334, 730, 690, 772], radius=21, fill=BLUE)

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
res = os.path.join(root, "android/app/src/main/res")
for folder, px in {"mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
                   "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192}.items():
    img.resize((px, px), Image.LANCZOS).save(os.path.join(res, folder, "ic_launcher.png"))
ios = os.path.join(root, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
for name in os.listdir(ios):
    if name.endswith(".png"):
        size = float(name.split("-")[-1].split("x")[0])
        scale = int(name.split("@")[1][0])
        px = round(size * scale)
        img.resize((px, px), Image.LANCZOS).save(os.path.join(ios, name))
img.save(os.path.join(root, "tool/icon/icon_1024.png"))
print("icons written")
