# -*- coding: utf-8 -*-
"""把 GPT Image 2.6 生成的原图（tools/art_src）加工成游戏素材。运行: python tools/make_art.py
  hand.png -> assets/fx/hand.png       胡牌时拍牌的手（透明底）
  coin.png -> assets/fx/seq_coin.png   金币旋转 8 帧图集
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'tools', 'art_src')
OUT = os.path.join(ROOT, 'assets', 'fx')

hand = Image.open(os.path.join(SRC, 'hand.png')).convert('RGBA')
hand.resize((460, 690), Image.LANCZOS).save(os.path.join(OUT, 'hand.png'))

coin = Image.open(os.path.join(SRC, 'coin.png')).convert('RGBA')
COLS, ROWS, FW = 4, 2, 128
cw, ch = coin.width / COLS, coin.height / ROWS
fh = int(round(FW * ch / cw))
sheet = Image.new('RGBA', (FW * COLS * ROWS, fh), (0, 0, 0, 0))
for i in range(COLS * ROWS):
    c, r = i % COLS, i // COLS
    cell = coin.crop((int(round(c * cw)), int(round(r * ch)), int(round((c + 1) * cw)), int(round((r + 1) * ch))))
    a = np.asarray(cell.resize((FW, fh), Image.LANCZOS)).astype(np.float32) / 255.0
    # 方孔和背景：原图透明或纯黑的地方都抠掉
    alpha = a[..., 3] * np.clip(a[..., :3].max(axis=2) * 7.0 - 0.25, 0, 1)
    rgba = np.dstack([a[..., :3], alpha])
    sheet.paste(Image.fromarray((rgba * 255).astype(np.uint8), 'RGBA'), (i * FW, 0))
sheet.save(os.path.join(OUT, 'seq_coin.png'))
print('hand', (460, 690), 'coin sheet', sheet.size)
