# -*- coding: utf-8 -*-
"""绿幕抠图 -> 748x1024 RGBA (33L)"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

SRC = "D:/星杯传说工程/星杯传说2/新建文件夹/task-mvf9981ud2y64-orig.png"
MASTER = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/_33L_master_2048.png"
OUT = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/_33L_final_748.png"
PREV_CHECKER = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/_33L_preview_checker.png"
PREV_DARK = "D:/星杯传说工程/星杯传说2/xianyu_xingbei/_33L_preview_dark.png"

LO, HI, HOLE = 25, 95, 500


def ge_of(rgb):
    r = rgb[..., 0].astype(np.int16)
    g = rgb[..., 1].astype(np.int16)
    b = rgb[..., 2].astype(np.int16)
    return g - np.maximum(r, b)


def chroma_cut(rgb, lo=LO, hi=HI):
    ge = ge_of(rgb)
    alpha = np.full(ge.shape, 255, dtype=np.uint8)
    solid = ge <= lo
    bg = ge >= hi
    mid = (~solid) & (~bg)
    t = (ge[mid].astype(np.float32) - lo) / (hi - lo)
    alpha[mid] = (255 * (1.0 - t)).astype(np.uint8)
    alpha[bg] = 0
    rgba = np.dstack([rgb.astype(np.uint8), alpha])
    return rgba


def fill_holes(rgba, hole_size):
    """不与画布边缘连通、且面积 <= hole_size 的透明块填回不透明。"""
    alpha = rgba[..., 3]
    transparent = alpha < 128
    lab, n = ndi.label(transparent)
    if n == 0:
        return rgba, 0
    border_labels = set(np.unique(np.concatenate([
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]])))
    sizes = np.bincount(lab.ravel())
    filled = 0
    for i in range(1, n + 1):
        if i in border_labels:
            continue
        if sizes[i] <= hole_size:
            m = lab == i
            rgba[..., 3][m] = 255
            filled += int(sizes[i])
    return rgba, filled


def degreen(rgba):
    out = rgba.copy()
    r = out[..., 0].astype(np.int16)
    g = out[..., 1].astype(np.int16)
    b = out[..., 2].astype(np.int16)
    out[..., 1] = np.minimum(g, np.maximum(r, b)).astype(np.uint8)
    return out


def checkerboard_preview(rgba, sq=16):
    h, w = rgba.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    c = (((xx // sq) + (yy // sq)) % 2) * 40 + 200
    bg = np.stack([c, c, c], axis=-1).astype(np.float32)
    a = rgba[..., 3:4].astype(np.float32) / 255.0
    return (rgba[..., :3].astype(np.float32) * a + bg * (1 - a)).astype(np.uint8)


def dark_preview(rgba, bgcol=(28, 30, 44)):
    h, w = rgba.shape[:2]
    bg = np.zeros((h, w, 3), np.float32)
    bg[:] = np.array(bgcol, np.float32)
    a = rgba[..., 3:4].astype(np.float32) / 255.0
    return (rgba[..., :3].astype(np.float32) * a + bg * (1 - a)).astype(np.uint8)


def stats(rgba, label):
    a = rgba
    al = a[..., 3]
    ge = ge_of(a[..., :3])
    ys, xs = np.nonzero(al > 128)
    return {
        'label': label,
        'size': f"{a.shape[1]}x{a.shape[0]}",
        'bg_clear_%': round(float((al == 0).mean() * 100), 2),
        'solid_%': round(float((al == 255).mean() * 100), 2),
        'semi_alpha_px': int(((al > 0) & (al < 255)).sum()),
        'green_residue_px': int(((ge > 3) & (al > 128)).sum()),
        'bbox': f"{xs.max()-xs.min()+1}x{ys.max()-ys.min()+1}",
        'bbox_xy': (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())),
        'bottom_gap': int(a.shape[0] - 1 - ys.max()),
    }


def main():
    src = Image.open(SRC).convert('RGB')
    rgb = np.array(src)
    ge = ge_of(rgb)
    print("[源图]", rgb.shape[1], 'x', rgb.shape[0])
    print("[绿幕纯度] bg_ge_median=%.0f  过渡带(25~95)=%.2f%%"
          % (float(np.median(ge[0:20].ravel())), float(((ge > LO) & (ge < HI)).mean() * 100)))

    rgba = chroma_cut(rgb, LO, HI)
    rgba = degreen(rgba)
    rgba, f1 = fill_holes(rgba, HOLE)
    print("[2048 抠图] 填洞像素", f1)
    Image.fromarray(rgba, 'RGBA').save(MASTER)
    print("[2048 指标]", stats(rgba, 'master'))

    # 缩放到 748x1024（LANCZOS）→ 再去绿 → 再补洞
    im = Image.fromarray(rgba, 'RGBA').resize((748, 1024), Image.LANCZOS)
    final = np.array(im)
    final = degreen(final)
    final, f2 = fill_holes(final, 60)
    print("[748 抠图] 填洞像素", f2)
    Image.fromarray(final, 'RGBA').save(OUT)
    s = stats(final, 'final')
    print("[终图指标]", s)

    Image.fromarray(checkerboard_preview(final), 'RGB').save(PREV_CHECKER)
    Image.fromarray(dark_preview(final), 'RGB').save(PREV_DARK)
    print("[输出]", OUT)


if __name__ == '__main__':
    main()
