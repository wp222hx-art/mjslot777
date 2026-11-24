# -*- coding: utf-8 -*-
"""从设计图谱中切出游戏素材。运行: python tools/slice.py"""
import os, sys, cv2, numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(ROOT), '麻将老虎机游戏界面与玩法设计咨询-assets-20261123')
OUT = os.path.join(ROOT, 'assets')

def load(n):
    return np.array(Image.open(os.path.join(SRC, n)).convert('RGB'))

def ivory_mask(img):
    r, g, b = [img[..., i].astype(int) for i in range(3)]
    m = (r > 185) & (g > 175) & (b > 140) & (r - b < 75) & (r >= g - 6)
    return m.astype(np.uint8) * 255

def find_tiles(img, region, min_area=9000, max_area=60000):
    x0, y0, x1, y1 = region
    sub = img[y0:y1, x0:x1]
    m = ivory_mask(sub)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    res = []
    for c in cnts:
        a = cv2.contourArea(c)
        if a < min_area or a > max_area:
            continue
        x, y, w, h = cv2.boundingRect(c)
        if w < 80 or h < 100:
            continue
        filled = np.zeros(m.shape, np.uint8)
        cv2.drawContours(filled, [cv2.convexHull(c)], -1, 255, -1)
        res.append((x + x0, y + y0, w, h, filled[y:y + h, x:x + w]))
    return res

def save_tile(img, box, name, size=(160, 200)):
    x, y, w, h, mask = box
    x += 2; y += 2; w -= 4; h -= 4
    rgb = img[y:y + h, x:x + w]
    im = Image.fromarray(whiten(rgb), 'RGB').resize(size, Image.LANCZOS).convert('RGBA')
    im.putalpha(round_mask(size, 22))
    im.save(os.path.join(OUT, 'tiles', name + '.png'))

def whiten(rgb):
    """把偏黄偏灰的象牙底校正成干净的白色：按牌面底色做白平衡并提亮，墨色图案保持饱和。"""
    a = rgb.astype(np.float32) / 255.0
    mx = a.max(axis=2); mn = a.min(axis=2)
    base = (mx > 0.72) & (mx - mn < 0.16)          # 牌面底色像素
    if base.sum() < 100:
        return rgb
    med = np.median(a[base], axis=0)                # 底色中位数 → 映射到近白
    out = a * (np.array([0.985, 0.985, 0.975], np.float32) / med)
    # 只对低饱和（底色与边缘阴影）区域再提一档亮度，保留一点立体感
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    w = np.clip(1.0 - sat / 0.30, 0, 1)[..., None]
    lifted = 1.0 - (1.0 - np.clip(out, 0, 1)) ** 1.35
    out = out * (1 - w) + lifted * w
    return (np.clip(out, 0, 1) * 255).astype(np.uint8)


def round_mask(size, rad):
    from PIL import ImageDraw, ImageFilter
    S = 4
    m = Image.new('L', (size[0] * S, size[1] * S), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] * S - 1, size[1] * S - 1), rad * S, fill=255)
    return m.resize(size, Image.LANCZOS)

K = 1.024  # 手工坐标取自 2000 宽预览图，原图为 2048 宽

def circle_crop(img, cx, cy, r, name, size=256, sub='ui'):
    from PIL import ImageDraw
    cx, cy, r = int(round(cx * K)), int(round(cy * K)), int(round(r * K))
    rgb = Image.fromarray(img[cy - r:cy + r, cx - r:cx + r], 'RGB').resize((size, size), Image.LANCZOS).convert('RGBA')
    S = 4
    m = Image.new('L', (size * S, size * S), 0)
    ImageDraw.Draw(m).ellipse((2, 2, size * S - 3, size * S - 3), fill=255)
    rgb.putalpha(m.resize((size, size), Image.LANCZOS))
    rgb.save(os.path.join(OUT, sub, name + '.png'))

def rect_crop(img, box, name, sub='ui', size=None, rad=0, feather=0, raw=False):
    x0, y0, x1, y1 = box if raw else [int(round(v * K)) for v in box]
    im = Image.fromarray(img[y0:y1, x0:x1], 'RGB')
    if size: im = im.resize(size, Image.LANCZOS)
    im = im.convert('RGBA')
    if rad: im.putalpha(round_mask(im.size, rad))
    if feather:
        w, h = im.size
        yy, xx = np.mgrid[0:h, 0:w]
        d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(float)
        a = np.clip(d / feather, 0, 1) ** 1.5
        im.putalpha(Image.fromarray((a * 255).astype(np.uint8), 'L'))
    im.save(os.path.join(OUT, sub, name + '.png'))

def rows_sorted(boxes, nrows):
    boxes = sorted(boxes, key=lambda b: b[1])
    ys = np.array([b[1] + b[3] / 2 for b in boxes])
    # 按 y 中心聚类
    order = np.argsort(ys)
    groups, cur = [], [boxes[order[0]]]
    for i in order[1:]:
        if ys[i] - (cur[-1][1] + cur[-1][3] / 2) > 60:
            groups.append(cur); cur = []
        cur.append(boxes[i])
    groups.append(cur)
    return [sorted(g, key=lambda b: b[0]) for g in groups]

report = []
# ---- 图谱 A: 万 筒 条 ----
a = load('02_tile_atlas_suits_fix.png')
rows = rows_sorted(find_tiles(a, (200, 150, 2048, 1090)), 3)
report.append(('A', [len(r) for r in rows]))
for suit, row in zip('mps', rows):
    for i, b in enumerate(row):
        save_tile(a, b, '%s%d' % (suit, i + 1))
# ---- 图谱 B: 风 箭 花 ----
b_ = load('03_tile_atlas_honors_flowers.png')
winds = sorted(find_tiles(b_, (100, 150, 1010, 370)), key=lambda t: t[0])
drags = sorted(find_tiles(b_, (1040, 150, 2000, 370)), key=lambda t: t[0])
seas = sorted(find_tiles(b_, (60, 470, 1010, 700)), key=lambda t: t[0])
flow = sorted(find_tiles(b_, (1040, 470, 2000, 700)), key=lambda t: t[0])
report.append(('B', [len(winds), len(drags), len(seas), len(flow)]))
for i, t in enumerate(winds): save_tile(b_, t, 'z%d' % (i + 1))
for i, t in enumerate(drags[:2]): save_tile(b_, t, 'z%d' % (i + 5))
save_tile(b_, (1693, 163, 180, 188, None), 'z7')
for i, t in enumerate(seas): save_tile(b_, t, 'f%d' % (i + 1))
for i, t in enumerate(flow): save_tile(b_, t, 'f%d' % (i + 5))
# ---- 特殊符号 ----
c = load('05_special_symbols.png')
circle_crop(c, 220, 364, 158, 'hu')
circle_crop(c, 613, 369, 160, 'wild')
rect_crop(c, (920, 186, 1084, 554), 'zhan', rad=10)
g = load('04_grade_materials.png')
for n, cy in zip(['badge_blue', 'badge_purple', 'badge_gold', 'badge_diamond'], [270, 438, 606, 773]):
    circle_crop(g, 1795, cy, 79, n, size=96)
# ---- 主持人 ----
h = load('11_host_duo_sheet.png')
for n, (cx, cy) in {'f_call': (700, 300), 'f_banter': (705, 580), 'f_win': (725, 850),
                    'm_serve': (1715, 300), 'm_appraise': (1700, 585), 'm_congrats': (1715, 835)}.items():
    circle_crop(h, cx, cy, 118 if n[0] == 'm' else 135, n, size=300, sub='host')
# ---- 元素特效图 ----
f = load('09_moment_fx_board_fix.png')
for n, box in {'wind': (30, 142, 660, 468), 'ice': (686, 142, 1316, 468), 'thunder': (1342, 142, 1972, 468),
               'fire': (30, 585, 660, 910), 'light': (1002, 585, 1316, 908), 'ink': (1342, 585, 1972, 906)}.items():
    rect_crop(f, box, 'el_' + n, sub='fx', feather=60)
# ---- 大图 ----
rect_crop(load('14_big_hand_host_showcase_fix.png'), (0, 0, 1152, 2048), 'bighand_still', sub='video', size=(720, 1280), raw=True)
rect_crop(load('10_story_minigame_teahouse_fix.png'), (0, 150, 1152, 914), 'story_still', sub='video', size=(720, 478), raw=True)
rect_crop(load('08_settlement_screen.png'), (0, 0, 1152, 864), 'hu_still', sub='video', size=(720, 540), raw=True)
rect_crop(load('01_style_master_board_textfix.png'), (600, 150, 1440, 780), 'table', sub='ui')
print(report)
