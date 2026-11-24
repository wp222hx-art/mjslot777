# -*- coding: utf-8 -*-
"""用 GPT Image 2.6 生成特效循环动画，并拆帧成序列帧图集。
运行: python tools/gen_fx.py [名称 ...]   不带参数 = 生成全部缺失项
产物: tools/fx_src/<名称>.png（原始 4x2 序列帧）  assets/fx/seq_<名称>.png（横向图集）
"""
import json, os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'tools', 'fx_src')
OUT = os.path.join(ROOT, 'assets', 'fx')
os.makedirs(SRC, exist_ok=True)

COLS, ROWS = 4, 2
BLACK = ("A game VFX sprite sheet: exactly 8 animation frames arranged in a strict grid of 4 columns and 2 rows, "
         "read left to right, top row first. Every cell is exactly the same size, the effect is centered inside its own "
         "cell and never crosses into a neighbouring cell. Pure solid black background (#000000) everywhere, no grid "
         "lines, no borders, no numbers, no text, no letters, no UI, no mahjong tiles, nothing except the effect. "
         "High contrast, glowing, painterly Chinese fantasy game style. ")

# 名称: (提示词, 比例, 帧间隔ms, 输出帧边长, 模式)   模式 add=黑底加色  ink=白底转墨色透明
FX = {
    'wind': (BLACK + "A swirling jade-green and mint wind vortex with a few small green leaves spinning around the center, "
             "soft translucent air ribbons. Animation: the vortex spins one full turn and expands slightly, seamless loop.", '2:1', 60, 256, 'add'),
    'burst': (BLACK + "A golden impact burst: a bright white-gold core flash, an expanding ring shockwave and flying golden sparks "
              "and small star glints. Animation: frame 1 a tiny bright point, then it explodes outward, the ring expands and "
              "the sparks fade to nothing by the last frame.", '2:1', 50, 256, 'add'),
    'ice': (BLACK + "An ice-blue frost burst: sharp ice crystals and snowflakes shooting outward from the center with cold "
            "cyan-white mist. Animation: crystals grow outward quickly from a point, then shatter into glittering shards "
            "that fade by the last frame.", '2:1', 60, 320, 'add'),
    'thunder': (BLACK + "Violet-purple lightning: several jagged electric bolts striking from the top edge down to the center "
                "with a bright white-violet flash and crackling small arcs. Animation: bolts flicker and branch differently "
                "each frame, strongest in the middle frames, fading at the end.", '1:1', 60, 256, 'add'),
    'fire': (BLACK + "A wide wall of roaring orange-gold flames rising from the bottom edge, with embers flying upward. "
             "Animation: flames lick and wave upward continuously, seamless loop.", '16:9', 70, 512, 'add'),
    'light': (BLACK + "A diamond prism light burst: brilliant white core with rainbow refraction rays and sparkling star "
              "glints radiating in all directions. Animation: the rays rotate slowly and the sparkles twinkle, seamless loop.", '2:1', 80, 320, 'add'),
    'goldglow': (BLACK + "A rising golden shimmer: warm gold light pillar with floating gold dust particles and small "
                 "four-point sparkles drifting upward. Animation: dust rises and sparkles twinkle, seamless loop.", '2:1', 70, 256, 'add'),
    'petals': (BLACK + "Pink plum blossom petals swirling in a gentle circular breeze with soft pink glow. Animation: "
               "petals swirl around the center one full turn, seamless loop.", '2:1', 70, 256, 'add'),
    'ring': (BLACK + "A thin glowing golden energy ring with tiny sparkles. Animation: the ring starts very small at the "
             "center and expands smoothly to the canvas edge while fading out by the last frame.", '2:1', 50, 256, 'add'),
    'ink': ("A game VFX sprite sheet: exactly 8 animation frames arranged in a strict grid of 4 columns and 2 rows, read left to right, "
            "top row first, every cell exactly the same size. Pure solid white background (#FFFFFF), no grid lines, no borders, no text. "
            "A single bold black Chinese ink brush slash stroke sweeping diagonally from upper right to lower left, "
            "with ink splatter droplets, sumi-e style. Animation: frame 1 empty white, then the stroke is drawn quickly "
            "across the canvas, ink splashes out, and it stays fully drawn in the last frames.", '16:9', 50, 512, 'ink'),
}


def generate(name):
    prompt, ratio, _dur, _size, _mode = FX[name]
    png = os.path.join(SRC, name + '.png')
    if os.path.exists(png) and os.path.getsize(png) > 20000:
        return name, 'cached'
    args = {'query': prompt, 'model': 'gpt-image-2.6', 'aspect_ratio': ratio, 'image_size': '2k'}
    with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8') as f:
        json.dump(args, f, ensure_ascii=False)
        path = f.name
    try:
        r = subprocess.run('gsk image_generation --args-file "%s" -o "%s"' % (path, png), shell=True, capture_output=True)
    finally:
        os.unlink(path)
    if os.path.exists(png) and os.path.getsize(png) > 20000:
        return name, 'ok'
    return name, 'FAIL rc=%d %s %s' % (r.returncode, r.stdout.decode('utf-8', 'replace')[:600], r.stderr.decode('utf-8', 'replace')[:300])


def pack(name):
    _prompt, _ratio, dur, size, mode = FX[name]
    # 模型输出自带透明通道：先垫到约定的底色上（特效垫黑、墨迹垫白），再统一换算透明度
    raw = Image.open(os.path.join(SRC, name + '.png')).convert('RGBA')
    under = Image.new('RGBA', raw.size, (255, 255, 255, 255) if mode == 'ink' else (0, 0, 0, 255))
    under.alpha_composite(raw)
    src = under.convert('RGB')
    cw, ch = src.width / COLS, src.height / ROWS
    fw = size
    fh = int(round(size * ch / cw))
    n = COLS * ROWS
    sheet = Image.new('RGBA', (fw * n, fh), (0, 0, 0, 0))
    yy, xx = np.mgrid[0:fh, 0:fw]
    edge = np.clip(np.minimum(np.minimum(xx, fw - 1 - xx) / (fw * 0.10), np.minimum(yy, fh - 1 - yy) / (fh * 0.10)), 0, 1)
    for i in range(n):
        c, r = i % COLS, i // COLS
        cell = src.crop((int(round(c * cw)), int(round(r * ch)), int(round((c + 1) * cw)), int(round((r + 1) * ch))))
        a = np.asarray(cell.resize((fw, fh), Image.LANCZOS)).astype(np.float32) / 255.0
        if mode == 'add':
            # 黑底：亮度作透明度，颜色反预乘
            alpha = np.clip(a.max(axis=2) * 1.3 - 0.06, 0, 1)
            rgb = np.clip(a / np.maximum(alpha[..., None], 1e-3), 0, 1)
        else:
            alpha = np.clip((1.0 - a.mean(axis=2)) * 1.3 - 0.06, 0, 1)
            rgb = np.zeros_like(a) + 0.03
        rgba = np.dstack([rgb, alpha * edge])
        sheet.paste(Image.fromarray((rgba * 255).astype(np.uint8), 'RGBA'), (i * fw, 0))
    sheet.save(os.path.join(OUT, 'seq_%s.png' % name))
    return {'frames': n, 'w': fw, 'h': fh, 'ms': dur, 'mode': mode}


if __name__ == '__main__':
    names = sys.argv[1:] or list(FX)
    with ThreadPoolExecutor(4) as ex:
        for n, st in ex.map(generate, names):
            print(n, st)
    meta_path = os.path.join(OUT, 'seq.json')
    meta = json.load(open(meta_path, encoding='utf-8')) if os.path.exists(meta_path) else {}
    for n in FX:
        if os.path.exists(os.path.join(SRC, n + '.png')):
            meta[n] = pack(n)
    json.dump(meta, open(meta_path, 'w', encoding='utf-8'), indent=1)
    print(json.dumps(meta))
