# -*- coding: utf-8 -*-
"""47L -> new47L：清除头发上的绿幕残留（最终版）

1) 绿幕残块（接近绿幕原色：ge=G-max(R,B) 高且 B 低、不在蛇身）→ 恢复透明，边缘 2px 渐隐
2) 黄绿过渡带 (ge 20~60) → alpha 渐隐
3) 暖色像素（R>B，头发/皮肤/裙子）去绿 G=min(G,max(R,B))，蛇的薄荷绿完全保护
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

# 蛇保护
mint = (b >= 150) & (g >= 180) & (r >= 90) & (al > 0)
mint_wide = ndi.binary_dilation(mint, np.ones((3, 3)), iterations=2)
protect = ndi.binary_erosion(mint, np.ones((3, 3)), iterations=2)

strong = (ge > 60) & (b < 160) & (al > 0) & ~protect
ring = ndi.binary_dilation(strong, ndi.generate_binary_structure(2, 2), iterations=2)
ring &= (ge > 20) & (al > 0) & ~protect

# 暖色去绿（蛇及其周围 2px 不动）
desp = (r > b) & (al > 0) & ~mint_wide
g2 = np.where(desp, np.minimum(g, np.maximum(r, b)), g)

out = a.copy()
out[..., 1] = g2.astype(np.uint8)
alf = al.astype(np.float32)
alf[strong] = 0
t = np.clip((ge[ring].astype(np.float32) - 20) / 40.0, 0, 1)
alf[ring] = np.clip(al[ring].astype(np.float32) * (1 - t), 0, 255)
out[..., 3] = alf.astype(np.uint8)

Image.fromarray(out, 'RGBA').save(OUT)

# ---- 校验（用输出 alpha）----
ao = out[..., 3]
r2, g2i, b2 = [out[..., i].astype(np.int16) for i in range(3)]
ge2 = g2i - np.maximum(r2, b2)
diff = (a.astype(int) != out.astype(int)).any(axis=2)
print("[尺寸]", out.shape[1], "x", out.shape[0], "RGBA")
print("[改动像素]", int(diff.sum()))
print("[改动到蛇内部]", int((diff & protect).sum()))
print("[改动到蛇保护区(含2px)]", int((diff & mint_wide).sum()))
print("[剩余纯绿 & 可见]", int(((r2 < 80) & (b2 < 80) & (g2i > 120) & (ao > 0)).sum()))
print("[剩余强绿 ge>60 & a>128]", int(((ge2 > 60) & (ao > 128)).sum()))
print("[绿边 ge>3 & a>128]", int(((ge2 > 3) & (ao > 128)).sum()))
print("[暖色去绿改动]", int((desp & (g2 != g) & (al > 0)).sum()))
ys, xs = np.nonzero(diff)
print("[改动 bbox]", (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())))


def comp(x, bg):
    aa = x[..., 3:4].astype(np.float32) / 255
    bb = np.zeros(x.shape[:2] + (3,), np.float32)
    bb[:] = bg
    return (x[..., :3].astype(np.float32) * aa + bb * (1 - aa)).astype(np.uint8)


Image.fromarray(comp(out, (28, 30, 44))).resize((768, 1050), Image.LANCZOS).save(BASE + '_new47_dark.png')
Image.fromarray(comp(out, (255, 255, 255))).resize((768, 1050), Image.LANCZOS).save(BASE + '_new47_white.png')
print("[输出]", OUT)
