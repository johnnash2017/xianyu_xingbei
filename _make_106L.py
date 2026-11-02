# -*- coding: utf-8 -*-
"""106L：绿幕抠图（条件填洞）-> 原尺寸 RGBA，原地保存"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
import _cut_33L as P

SRC = "D:/星杯传说工程/星杯传说2/角色立绘去除绿幕/task-mvz41enf16mw1d-orig.png"
OUT = "D:/星杯传说工程/星杯传说2/角色立绘去除绿幕/106L.png"
BASE = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/"


def fill_holes_smart(rgba, ge, hole_size, green_thr=80):
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
        if float(ge[m].mean()) < green_thr:
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
print("[指标]", P.stats(rgba, '106L'))
Image.fromarray(rgba, 'RGBA').save(OUT)

Image.fromarray(P.checkerboard_preview(rgba), 'RGB').resize((512, 700), Image.LANCZOS).save(BASE + '_106_checker.png')
dark = P.dark_preview(rgba)
Image.fromarray(dark).resize((512, 700), Image.LANCZOS).save(BASE + '_106_dark.png')

def comp(x, bg):
    aa = x[..., 3:4].astype(np.float32) / 255
    bb = np.zeros(x.shape[:2] + (3,), np.float32); bb[:] = bg
    return (x[..., :3].astype(np.float32) * aa + bb * (1 - aa)).astype(np.uint8)

Image.fromarray(comp(rgba, (240, 238, 232))).resize((512, 700), Image.LANCZOS).save(BASE + '_106_light.png')

regions = {'face': (600, 100, 1300, 800), 'pillow': (1450, 700, 2048, 1400), 'hair': (300, 700, 700, 1500), 'sock': (200, 2100, 900, 2700)}
tiles = [Image.fromarray(dark[y0:y1, x0:x1]) for (x0, y0, x1, y1) in regions.values()]
W = sum(t.width for t in tiles) + 10 * len(tiles); H = max(t.height for t in tiles)
sheet = Image.new('RGB', (W, H), (60, 60, 60)); x = 0
for t in tiles: sheet.paste(t, (x, 0)); x += t.width + 10
sheet.save(BASE + '_106_zoom.png')
print("[输出]", OUT)
