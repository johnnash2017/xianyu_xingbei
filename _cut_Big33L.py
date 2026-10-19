# -*- coding: utf-8 -*-
"""绿幕原图 -> 2048x2800 透明版 Big33L（原生分辨率，不缩放）"""
import numpy as np
from PIL import Image
import _cut_33L as P

SRC = "D:/星杯传说工程/星杯传说2/新建文件夹/task-mvf9981ud2y64-orig.png"
OUT = "D:/星杯传说工程/星杯传说2/新建文件夹/Big33L.png"

rgb = np.array(Image.open(SRC).convert('RGB'))
ge = P.ge_of(rgb)
print("[源图] %dx%d  绿幕纯度 bg_ge_median=%.0f  过渡带(25~95)=%.2f%%"
      % (rgb.shape[1], rgb.shape[0], float(np.median(ge[0:20].ravel())),
         float(((ge > P.LO) & (ge < P.HI)).mean() * 100)))

rgba = P.chroma_cut(rgb, P.LO, P.HI)
rgba = P.degreen(rgba)
rgba, filled = P.fill_holes(rgba, P.HOLE)
# 兜底：再做一次全局去绿（幂等）
rgba = P.degreen(rgba)

Image.fromarray(rgba, 'RGBA').save(OUT)
print("[填洞]", filled)
print("[指标]", P.stats(rgba, 'Big33L'))
print("[输出]", OUT)
