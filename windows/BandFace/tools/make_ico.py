# SPDX-License-Identifier: MIT
# Значок exe для Windows: завжди з ТЕМНОЇ версії значка iOS (AppIcon icon-dark.png), квадратний, без заокруглення.
# Запуск: python tools/make_ico.py <шлях до icon-dark.png>  → Assets/app.ico (16…256 px)
import sys, os
from PIL import Image

src = Image.open(sys.argv[1]).convert("RGBA")
sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
out = os.path.join(os.path.dirname(__file__), "..", "Assets", "app.ico")
src.save(out, sizes=[(s, s) for s in sizes])
print("written", out)
