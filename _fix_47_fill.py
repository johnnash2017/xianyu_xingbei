# -*- coding: utf-8 -*-
"""47L 绿块修补（水平插值填充版）测试"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

a = np.array(Image.open('D:/星杯传说工程/星杯传说2/角色立绘去除绿幕/47L.png').convert('RGBA'))
H, W = a.shape[:2]
al = a[..., 3]
r, g, b = [a[..., i].astype(np.int16) for i in range(3)]
ge = g - np.maximum(r, b)

mint = (b >= 150) & (g >= 180) & (r >= 90) & (al > 0)
protect = ndi.binary_erosion(mint, np.ones((3, 3)), iterations=2)

strong = (ge > 60) & (b < 160) & (al > 0) & ~protect
ring = ndi.binary_dilation(strong, ndi.generate_binary_structure(2, 2), iterations=2) & (ge > 15) & (al > 0) & ~protect
mask = strong | ring
valid = (~mask) & (al >= 200) & (ge <= 0)
print("mask", int(mask.sum()), "valid", int(valid.sum()))

out = a.astype(np.float32).copy()
filled_rows = np.zeros((H, W), bool)

for y in range(H):
    mrow = mask[y]
    if not mrow.any():
        continue
    xs = np.nonzero(mrow)[0]
    # 找连续段
    breaks = np.where(np.diff(xs) > 1)[0]
    starts = np.concatenate(([0], breaks + 1))
    ends = np.concatenate((breaks, [len(xs) - 1]))
    vrow = valid[y]
    for si, ei in zip(starts, ends):
        s, e = xs[si], xs[ei]
        lx = None
        for x in range(s - 1, max(s - 60, -1), -1):
            if vrow[x]:
                lx = x
                break
        rx = None
        for x in range(e + 1, min(e + 60, W)):
            if vrow[x]:
                rx = x
                break
        if lx is not None and rx is not None:
            t = (np.arange(s, e + 1, dtype=np.float32) - lx) / float(rx - lx)
            out[y, s:e + 1, :3] = (1 - t)[:, None] * a[y, lx, :3] + t[:, None] * a[y, rx, :3]
            filled_rows[y, s:e + 1] = True
        elif lx is not None:
            out[y, s:e + 1, :3] = a[y, lx, :3]
            filled_rows[y, s:e + 1] = True
        elif rx is not None:
            out[y, s:e + 1, :3] = a[y, rx, :3]
            filled_rows[y, s:e + 1] = True

# 剩余（水平两侧都没有）用最近有效像素填
rest = mask & ~filled_rows
if rest.any():
    ind = ndi.distance_transform_edt(~valid, return_distances=False, return_indices=True)
    out[rest, :3] = a[ind[0][rest], ind[1][rest], :3]
print("horizontal filled", int(filled_rows.sum()), "rest", int(rest.sum()))

# mask 内轻微平滑
img = out[..., :3].copy()
for _ in range(20):
    blur = ndi.uniform_filter(img, size=(3, 3, 1))
    img[mask] = blur[mask]
out[..., :3] = img
out[..., 3] = a[..., 3]
res = out.astype(np.uint8)
Image.fromarray(res, 'RGBA').save('D:/星杯传说工程/星杯传说2/xianyu_xingbei/_47_varI.png')

r2, g2, b2 = [res[..., i].astype(np.int16) for i in range(3)]
ge2 = g2 - np.maximum(r2, b2)
print("remaining pure", int(((r2 < 80) & (b2 < 80) & (g2 > 120) & (al > 0)).sum()),
      "strong", int(((ge2 > 60) & (al > 0)).sum()))


def comp(x, bg):
    aa = x[..., 3:4].astype(np.float32) / 255
    bb = np.zeros(x.shape[:2] + (3,), np.float32)
    bb[:] = bg
    return (x[..., :3].astype(np.float32) * aa + bb * (1 - aa)).astype(np.uint8)


regions = [(815, 340, 890, 480), (1180, 1190, 1260, 1340), (1060, 20, 1200, 160)]
for bgname, bg in [('w', (255, 255, 255)), ('d', (28, 30, 44))]:
    c = comp(res, bg)
    tiles = [Image.fromarray(c[y0:y1, x0:x1]).resize(((x1 - x0) * 5, (y1 - y0) * 5), Image.NEAREST) for (x0, y0, x1, y1) in regions]
    Wt = sum(t.width for t in tiles) + 10 * len(tiles)
    Ht = max(t.height for t in tiles)
    sheet = Image.new('RGB', (Wt, Ht), bg)
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width + 10
    sheet.save(f'D:/星杯传说工程/星杯传说2/xianyu_xingbei/_47_varI_{bgname}.png')
print('ok')
