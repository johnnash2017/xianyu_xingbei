# -*- coding: utf-8 -*-
"""武士大肥鱼：绿幕抠图 + 阴影绿去除 -> 原尺寸 RGBA，原地保存

流程：
1) 色度键 lo=25 / hi=95，去绿 G=min(G,max(R,B))
2) 条件填洞：只填“非绿幕色”的小洞，真实绿幕缝隙保持透明
3) 阴影绿修正：绿幕被头发遮暗后会变成青绿色（G≈B，色度键判不出来），
   针对这类“低 R、G 比 B 不低”的暗部，把 B 提到 G+28，使其并入蓝色发影，
   不再呈现绿色块。
"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
import _cut_33L as P

SRC = "D:/星杯传说工程/星杯传说2/角色立绘去除绿幕/task-mvy9u0jc1244kg-orig.png"
OUT = "D:/星杯传说工程/星杯传说2/角色立绘去除绿幕/武士大肥鱼.png"
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


src = np.array(Image.open(SRC).convert('RGB'))
ge = P.ge_of(src)
print("[源图] %dx%d  背景 ge 中位=%.0f  过渡带(25~95)=%.2f%%"
      % (src.shape[1], src.shape[0], float(np.median(ge[:20].ravel())),
         float(((ge > P.LO) & (ge < P.HI)).mean() * 100)))

rgba = P.chroma_cut(src, P.LO, P.HI)
rgba = P.degreen(rgba)
rgba, filled, kept = fill_holes_smart(rgba, ge, P.HOLE)
rgba = P.degreen(rgba)
print("[条件填洞] 填回 %d px（绿色缝隙保留透明 %d px）" % (filled, kept))

# ---- 阴影绿修正 ----
sr, sg, sb = [src[..., i].astype(np.int16) for i in range(3)]
al = rgba[..., 3]
teal_green = (sg - sb > -25) & (sg > sr + 35) & (al > 128)
print("[阴影绿像素]", int(teal_green.sum()))
r2, g2, b2 = [rgba[..., i].astype(np.int16) for i in range(3)]
b2 = np.where(teal_green, np.clip(g2 + 28, 0, 255), b2)
g2 = np.minimum(g2, np.maximum(r2, b2))
rgba[..., 1] = g2.astype(np.uint8)
rgba[..., 2] = b2.astype(np.uint8)

print("[指标]", P.stats(rgba, '武士大肥鱼'))
Image.fromarray(rgba, 'RGBA').save(OUT)

Image.fromarray(P.checkerboard_preview(rgba), 'RGB').resize((512, 700), Image.LANCZOS).save(BASE + '_samurai_checker.png')
dark = P.dark_preview(rgba)
Image.fromarray(dark).resize((512, 700), Image.LANCZOS).save(BASE + '_samurai_dark.png')

def comp(x, bg):
    aa = x[..., 3:4].astype(np.float32) / 255
    bb = np.zeros(x.shape[:2] + (3,), np.float32); bb[:] = bg
    return (x[..., :3].astype(np.float32) * aa + bb * (1 - aa)).astype(np.uint8)

Image.fromarray(comp(rgba, (240, 238, 232))).resize((512, 700), Image.LANCZOS).save(BASE + '_samurai_light.png')

# 1:1 局部
regions = {'face': (600, 50, 1250, 700), 'apron': (700, 900, 1350, 1500), 'tail': (1500, 1750, 2048, 2500)}
tiles = [Image.fromarray(dark[y0:y1, x0:x1]) for (x0, y0, x1, y1) in regions.values()]
W = sum(t.width for t in tiles) + 10 * len(tiles); H = max(t.height for t in tiles)
sheet = Image.new('RGB', (W, H), (60, 60, 60)); x = 0
for t in tiles: sheet.paste(t, (x, 0)); x += t.width + 10
sheet.save(BASE + '_samurai_zoom.png')
print("[输出]", OUT)
