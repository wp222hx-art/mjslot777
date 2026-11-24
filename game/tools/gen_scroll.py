# -*- coding: utf-8 -*-
"""集齐动画用的横幅长卷（GPT Image 2.6，21:9）。运行: python tools/gen_scroll.py [名称 ...]
产物: tools/art_src/scroll_<名称>.png（原图）  assets/fx/scroll_<名称>.jpg（高 900 的长卷）
  seasons 春夏秋冬（四季花牌）   junzi 梅兰竹菊（四君子花牌）   wind 东南西北风（风位）
画面从左到右依次展开，游戏里让它自右向左横穿屏幕。
"""
import json, os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'tools', 'art_src')
OUT = os.path.join(ROOT, 'assets', 'fx')
H = 900

BASE = ("An ultra-wide horizontal Chinese handscroll painting, one continuous seamless panorama read from left to right. "
        "Refined gongbi brushwork blended with ink wash, rich jewel colours, luminous golden mist and soft glowing light, "
        "dreamlike and poetic, premium mobile game splash art quality. The composition fills the whole canvas edge to edge "
        "with no empty margins. Absolutely no text, no calligraphy, no seals, no stamps, no people, no borders, no frames, "
        "no mahjong tiles. ")

ART = {
    'seasons': BASE + ("The four seasons flow into each other in four equal parts: far left is SPRING with pink peach and "
                       "cherry blossoms, fresh green willow and flying swallows; then SUMMER with a lotus pond, big green "
                       "lotus leaves, pink lotus flowers and dragonflies under warm sunlight; then AUTUMN with blazing red "
                       "maple and golden ginkgo leaves drifting in the wind over a misty mountain stream; far right is "
                       "WINTER with snow-covered pines, falling snowflakes and a red plum branch in the moonlight. "
                       "The colour temperature shifts smoothly pink, green, gold-red, cool blue-white."),
    'junzi': BASE + ("The Four Gentlemen plants in four equal parts: far left a gnarled PLUM branch covered in red and "
                     "white blossoms with light snow; then elegant ORCHIDS with long arching leaves and pale purple "
                     "flowers beside a mossy rock; then a grove of tall green BAMBOO with leaves swaying in a breeze and "
                     "shafts of light; far right lush golden and white CHRYSANTHEMUMS beside a rustic fence in autumn "
                     "sunset light. Scholarly, serene, fragrant atmosphere with drifting petals across the whole scroll."),
    'wind': BASE + ("A great wind sweeps across the whole landscape from left to right: long flowing ribbons of jade-green "
                    "and white wind, swirling auspicious clouds, bending willows and bamboo, thousands of leaves and "
                    "petals streaming sideways, silk streamers and paper kites flying, white cranes gliding on the wind, "
                    "distant blue-green mountains and a pagoda with swinging wind bells, rippling water below. "
                    "Strong sense of fast horizontal motion and fresh air, teal, jade and gold palette."),
}


def generate(name):
    png = os.path.join(SRC, 'scroll_%s.png' % name)
    if not (os.path.exists(png) and os.path.getsize(png) > 100000):
        args = {'query': ART[name], 'model': 'gpt-image-2.6', 'aspect_ratio': '21:9', 'image_size': '2k'}
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8') as f:
            json.dump(args, f, ensure_ascii=False)
            path = f.name
        try:
            for _attempt in range(2):
                r = subprocess.run('gsk image_generation --args-file "%s" -o "%s"' % (path, png), shell=True, capture_output=True)
                if os.path.exists(png) and os.path.getsize(png) > 100000:
                    break
        finally:
            os.unlink(path)
        if not (os.path.exists(png) and os.path.getsize(png) > 100000):
            return name, 'FAIL ' + r.stdout.decode('utf-8', 'replace')[:400] + r.stderr.decode('utf-8', 'replace')[:200]
    im = Image.open(png).convert('RGB')
    w = int(round(im.width * H / im.height))
    im.resize((w, H), Image.LANCZOS).save(os.path.join(OUT, 'scroll_%s.jpg' % name), quality=90)
    return name, 'ok %dx%d (src %dx%d)' % (w, H, im.width, im.height)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    names = sys.argv[1:] or list(ART)
    with ThreadPoolExecutor(3) as ex:
        for n, st in ex.map(generate, names):
            print(n, st)
