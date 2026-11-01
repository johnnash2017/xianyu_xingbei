# -*- coding: utf-8 -*-
"""47L 去绿块 -> new47L.png
   思路：47L 里残留的是“纯绿幕色”像素（高饱和绿，R/B 都很低）。
   蛇是薄荷绿（B/G 高），用颜色掩膜保护，只清理绿色残块：
   - 强绿块 (ge>60)：alpha 归零（这些本来就是被误填成不透明的绿幕空隙）
   - 周边一圈黄绿过渡 (ge 20~60)：alpha 渐隐 + 去绿，避免硬边
   - 蛇身内部完全不改动
"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

SRC = "D:/星杯传说工程/星杯传说2/角色立绘去除绿幕/47L.png"
OUT = "D:/星杯传说工程/星杯传说2/角色立绘去除绿幕/new47L.png"
BASE = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/"

a = np.array(Image.open(SRC).convert('RGBA'))
al = a[..., 3]
r, g, b = [a[..., i].astype(np.int16) for i in range(3)]
ge = g - np.maximum(r, b)

# 蛇的保护罩：薄荷绿（B、G 都高），内缩 2px，允许修掉蛇边缘的绿色反光
mint = (b >= 150) & (g >= 180) & (r >= 90) & (al > 0)
protect = ndi.binary_erosion(mint, np.ones((3, 3)), iterations=2)

strong = (ge > 60) & (b < 160) & (al > 0) & ~protect
ring = ndi.binary_dilation(strong, ndi.generate_binary_structure(2, 2), iterations=2)
ring &= (ge > 20) & (al > 0) & ~protect

out = a.copy()
alf = al.astype(np.float32)
alf[strong] = 0
t = np.clip((ge[ring].astype(np.float32) - 20) / 40.0, 0, 1)
alf[ring] = np.clip(al[ring].astype(np.float32) * (1 - t), 0, 255)
out[..., 3] = alf.astype(np.uint8)
out[..., 1] = np.where(ring, np.minimum(g, np.maximum(r, b)), g).astype(np.uint8)

Image.fromarray(out, 'RGBA').save(OUT)

# ---- 校验 ----
r2, g2, b2 = [out[..., i].astype(np.int16) for i in range(3)]
ge2 = g2 - np.maximum(r2, b2)
diff = (a.astype(int) != out.astype(int)).any(axis=2)
print("[尺寸]", out.shape[1], "x", out.shape[0])
print("[改动像素]", int(diff.sum()), " 其中改到蛇内部的:", int((diff & protect).sum()))
print("[剩余纯绿 px]", int(((r2 < 80) & (b2 < 80) & (g2 > 120) & (al > 0)).sum()))
print("[剩余强绿 ge>60]", int(((ge2 > 60) & (al > 0)).sum()), " 其中蛇内部:", int(((ge2 > 60) & (al > 0) & protect).sum()))
print("[改动分布 bbox]", end=" ")
ys, xs = np.nonzero(diff)
print((int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())))


def comp(x, bg):
    aa = x[..., 3:4].astype(np.float32) / 255
    bb = np.zeros(x.shape[:2] + (3,), np.float32)
    bb[:] = bg
    return (x[..., :3].astype(np.float32) * aa + bb * (1 - aa)).astype(np.uint8)


Image.fromarray(comp(out, (28, 30, 44))).resize((768, 1050), Image.LANCZOS).save(BASE + '_47L_new_dark.png')
Image.fromarray(comp(out, (255, 255, 255))).resize((768, 1050), Image.LANCZOS).save(BASE + '_47L_new_white.png')
print("[输出]", OUT)
