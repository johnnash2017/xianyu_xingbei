# -*- coding: utf-8 -*-
"""47L 修绿块：识别绿幕残留（饱和绿），保护薄荷绿蛇，用周围颜色修补"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

SRC = "D:/星杯传说工程/星杯传说2/角色立绘去除绿幕/47L.png"
TEST = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/_47_test_fixed.png"
BASE = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/"

a = np.array(Image.open(SRC).convert('RGBA'))
al = a[..., 3].astype(np.int16)
r, g, b = [a[..., i].astype(np.int16) for i in range(3)]
ge = g - np.maximum(r, b)

# 1) 绿幕残留：偏饱和的绿（低 R/B），排除薄荷绿的蛇
core = (ge > 20) & (b < 160) & (al > 0)
# 2) 蛇的保护罩：薄荷绿（B 高、G 高）
snake = (b >= 150) & (g >= 180) & (r >= 90) & (al > 0)
snake = ndi.binary_dilation(snake, np.ones((5, 5)))

# 3) 把残留连同其黄绿过渡边一起扩 3px，但不侵入蛇
mask = ndi.binary_dilation(core, ndi.generate_binary_structure(2, 2), iterations=3)
mask &= ~snake
mask &= (al > 0)
print("core px", int(core.sum()), "mask px", int(mask.sum()))

# 4) 最近有效像素填充（源：非 mask、较不透明）
src_ok = (~mask) & (al >= 200)
ind = ndi.distance_transform_edt(~src_ok, return_distances=False, return_indices=True)
filled = a.astype(np.float32).copy()
filled[mask, :3] = a[ind[0][mask], ind[1][mask], :3]

# 5) 在 mask 内做扩散平滑（保留边界颜色，内部平滑过渡）
img = filled[..., :3].copy()
m3 = mask
for _ in range(60):
    blur = ndi.uniform_filter(img, size=(3, 3, 1))
    img[m3] = blur[m3]
filled[..., :3] = img

out = filled.astype(np.uint8)
out[..., 3] = a[..., 3]

# 6) 检查
r2, g2, b2 = [out[..., i].astype(np.int16) for i in range(3)]
ge2 = g2 - np.maximum(r2, b2)
res = (ge2 > 20) & (b2 < 160) & (al > 0)
print("剩余饱和绿 px", int(res.sum()))
snake_after_ok = np.array_equal(out[snake], a[snake])
print("蛇区域未改动:", snake_after_ok)
print("max ge after:", int(ge2[al > 128].max()))

Image.fromarray(out, 'RGBA').save(TEST)

# 预览
def comp(x, bg):
    aa = x[..., 3:4].astype(np.float32) / 255
    bb = np.zeros(x.shape[:2] + (3,), np.float32); bb[:] = bg
    return (x[..., :3].astype(np.float32) * aa + bb * (1 - aa)).astype(np.uint8)

Image.fromarray(comp(out, (255, 255, 255))).resize((768, 1050), Image.LANCZOS).save(BASE + '_47_fixed_white.png')
Image.fromarray(comp(out, (28, 30, 44))).resize((768, 1050), Image.LANCZOS).save(BASE + '_47_fixed_dark.png')
print("done")
