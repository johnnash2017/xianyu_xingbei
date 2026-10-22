# -*- coding: utf-8 -*-
"""37L 系列：绿幕抠图 -> 37LD(2048x2800) + 37L(748x1024)，原地输出到源图所在目录"""
import numpy as np
from PIL import Image
import _cut_33L as P

SRC = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/task-mvj4imxuoap2h-orig.png"
BASE = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/"
OUT_BIG = BASE + "37LD.png"
OUT_SMALL = BASE + "37L.png"

rgb = np.array(Image.open(SRC).convert('RGB'))
ge = P.ge_of(rgb)
print("[源图] %dx%d  背景 ge 中位=%.0f  过渡带(25~95)=%.2f%%"
      % (rgb.shape[1], rgb.shape[0], float(np.median(ge[:20].ravel())),
         float(((ge > P.LO) & (ge < P.HI)).mean() * 100)))

rgba = P.chroma_cut(rgb, P.LO, P.HI)
rgba = P.degreen(rgba)
rgba, filled = P.fill_holes(rgba, P.HOLE)
rgba = P.degreen(rgba)
print("[37LD 填洞]", filled)
print("[37LD 指标]", P.stats(rgba, '37LD'))
Image.fromarray(rgba, 'RGBA').save(OUT_BIG)

# 748x1024
im = Image.fromarray(rgba, 'RGBA').resize((748, 1024), Image.LANCZOS)
small = np.array(im)
small = P.degreen(small)                 # 缩放后再去绿
small, f2 = P.fill_holes(small, 60)
print("[37L 填洞]", f2)
print("[37L 指标]", P.stats(small, '37L'))
Image.fromarray(small, 'RGBA').save(OUT_SMALL)

# 预览
for tag, arr in [('big', rgba), ('small', small)]:
    Image.fromarray(P.checkerboard_preview(arr), 'RGB').save(BASE + f'_37{tag}_checker.png')
    Image.fromarray(P.dark_preview(arr), 'RGB').save(BASE + f'_37{tag}_dark.png')
print("[输出]", OUT_BIG, OUT_SMALL)
