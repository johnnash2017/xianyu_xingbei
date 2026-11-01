# -*- coding: utf-8 -*-
"""78M：绿幕抠图（条件填洞：只填“非绿幕色”的误删洞）-> 原尺寸 2048x2800 RGBA"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
import _cut_33L as P

SRC = "D:/星杯传说工程/星杯传说2/角色立绘去除绿幕/task-mvw8vymm38ka9-orig.png"
OUT = "D:/星杯传说工程/星杯传说2/角色立绘去除绿幕/78M.png"
BASE = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/"


def fill_holes_smart(rgba, ge, hole_size, green_thr=80):
    """只填“不像绿幕”的小洞；绿色背景缝隙保持透明。"""
    alpha = rgba[..., 3]
    transparent = alpha < 128
    lab, n = ndi.label(transparent)
    border = set(np.unique(np.concatenate([lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]])))
    sizes = np.bincount(lab.ravel())
    filled, kept = 0, 0
    for i in range(1, n + 1):
        if i in border or sizes[i] > hole_size:
            continue
        m = lab == i
        ge_mean = float(ge[m].mean())
        if ge_mean < green_thr:
            rgba[..., 3][m] = 255
            filled += int(sizes[i])
        else:
            kept += int(sizes[i])
    return rgba, filled, kept


rgb = np.array(Image.open(SRC).convert('RGB'))
ge = P.ge_of(rgb)
print("[源图] %dx%d  背景 ge 中位=%.0f  过渡带(25~95)=%.2f%%"
      % (rgb.shape[1], rgb.shape[0], float(np.median(ge[:20].ravel())),
         float(((ge > P.LO) & (ge < P.HI)).mean() * 100)))

rgba = P.chroma_cut(rgb, P.LO, P.HI)
rgba = P.degreen(rgba)
rgba, filled, kept = fill_holes_smart(rgba, ge, P.HOLE)
rgba = P.degreen(rgba)
print("[条件填洞] 填回 %d px（绿色缝隙保留透明 %d px）" % (filled, kept))
print("[指标]", P.stats(rgba, '78M'))
Image.fromarray(rgba, 'RGBA').save(OUT)

Image.fromarray(P.checkerboard_preview(rgba), 'RGB').resize((512, 700), Image.LANCZOS).save(BASE + '_78_checker.png')
dark = P.dark_preview(rgba)
Image.fromarray(dark).resize((512, 700), Image.LANCZOS).save(BASE + '_78_dark.png')

crops = {'dress': (300, 1000, 900, 1600), 'hair': (450, 250, 1100, 900), 'book': (1250, 350, 1750, 750)}
tiles = []
for n, (x0, y0, x1, y1) in crops.items():
    tiles.append(Image.fromarray(dark[y0:y1, x0:x1]))
W = sum(t.width for t in tiles) + 10 * len(tiles); H = max(t.height for t in tiles)
sheet = Image.new('RGB', (W, H), (60, 60, 60)); x = 0
for t in tiles: sheet.paste(t, (x, 0)); x += t.width + 10
sheet.save(BASE + '_78_zoom.png')
print("[输出]", OUT)
