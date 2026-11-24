# -*- coding: utf-8 -*-
"""主持人语音：短促、有激情的喊话。用 Gemini 3.8 Flash TTS 生成，ffmpeg 统一响度并转 mp3。
运行: python tools/gen_vo.py [键名 ...]    不带参数 = 生成全部缺失项
产物: assets/audio/vo/<键名>.mp3    原始文件缓存在 tools/vo_src/
"""
import json, os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'tools', 'vo_src')
OUT = os.path.join(ROOT, 'assets', 'audio', 'vo')
os.makedirs(SRC, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

VOICE = 'Leda'
STYLE = 'young woman, thrilled mahjong game host shouting with explosive excitement, high energy, fast and punchy'
# 胡牌 / 大牌 / 大奖：情绪顶格
STYLE_HOT = 'young woman, ecstatic mahjong game host screaming with joy at the top of her voice, triumphant, explosive, breathless excitement'
HOT_PREFIX = ('hu_', 'big_', 'bigwin', 'superwin', 'draw_top')

NUM = ['一', '二', '三', '四', '五', '六', '七', '八', '九']
TILES = {}
for i in range(9):
    TILES['m%d' % (i + 1)] = NUM[i] + '万'
    TILES['p%d' % (i + 1)] = NUM[i] + '筒'
    TILES['s%d' % (i + 1)] = NUM[i] + '条'
for i, n in enumerate(['东风', '南风', '西风', '北风', '红中', '发财', '白板']):
    TILES['z%d' % (i + 1)] = n

# 与 scripts/core.gd 的 TEMPLATES / BIG_HANDS 保持一致：[id, 牌型名, 番种参考的念法]
TEMPLATES = [
    ('qys_pph', '清一色碰碰和', '六番'),
    ('duanyao', '断幺', '两番'),
    ('qidui', '七对', '二十四番'),
    ('hunyise', '混一色', '六番'),
    ('sansetong', '三色三同顺', '八番'),
]
BIG = [
    ('ssy', '十三幺', '八十八番'),
    ('qd', '七对', '二十四番'),
    ('qys', '清一色', '二十四番'),
    ('dsy', '大三元', '八十八番'),
    ('zys', '字一色', '六十四番'),
]

LINES = {
    'peng': '碰！',
    'chi': '吃！',
    'dui': '对！',
    'in1': '进了！',
    'in2': '好牌！',
    'in3': '漂亮！',
    'combo': '连消！',
    'combo2': '再连！',
    'gold': '黄金牌！',
    'diamond': '钻石牌！',
    'flower': '花齐了！',
    'wind': '四风齐！',
    'ready': '牌齐了！等胡！',
    'hu_invalid': '牌没齐，不算！',
    'zhan': '斩！',
    'aid': '送你一张！',
    'draw': '钻石局！抽大奖！',
    'draw_top': '命中大奖！！',
    'big_ting': '大牌听牌了！',
    'bigwin': '大奖！！',
    'superwin': '超级大奖！！！',
}
# 集齐的雅称：与 scripts/core.gd 的 BONUS_NAMES 保持一致；档位 0 普通 / 1 快 / 2 极快
BONUS = {
    'flower0': ['四季平安', '四季如花', '岁岁繁花'],
    'flower1': ['四君子', '兰亭雅集', '香满乾坤'],
    'wind': ['四风齐', '东南西北风', '风生水起'],
}
for bk, names in BONUS.items():
    for ti, nm in enumerate(names):
        LINES['bonus_%s_%d' % (bk, ti)] = nm + ('！！' if ti == 2 else '！')
for tid, name, fan in TEMPLATES:
    LINES['start_' + tid] = '这局做%s！%s！' % (name, fan)
    LINES['hu_' + tid] = '胡了！！%s！%s！' % (name, fan)
for bid, name, fan in BIG:
    LINES['big_' + bid] = '%s！！%s！太厉害了！' % (name, fan)
for tid, name in TILES.items():
    LINES['ting_dan_' + tid] = '听牌！单钓%s！' % name
    LINES['ting_' + tid] = '听牌！就差%s！' % name


def generate(key):
    raw = os.path.join(SRC, key + '.raw')
    dst = os.path.join(OUT, key + '.mp3')
    if os.path.exists(dst) and os.path.getsize(dst) > 1500 and os.path.exists(raw):
        return key, 'cached'
    if not (os.path.exists(raw) and os.path.getsize(raw) > 1500):
        args = {'prompt': LINES[key], 'model': 'google/gemini-3.8-flash-tts', 'audio_type': 'speech', 'file_name': key,
                'params': {'speakers': [{'speaker': 'Speaker1', 'voice_name': VOICE}],
                           'instructions': STYLE_HOT if (key.startswith(HOT_PREFIX) and key != 'hu_invalid' and key != 'big_ting') or (key.startswith('bonus_') and key.endswith('_2')) else STYLE}}
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8') as f:
            json.dump(args, f, ensure_ascii=False)
            path = f.name
        try:
            for _attempt in range(2):
                r = subprocess.run('gsk audio_generation --args-file "%s" -o "%s"' % (path, raw), shell=True, capture_output=True)
                if os.path.exists(raw) and os.path.getsize(raw) > 1500:
                    break
        finally:
            os.unlink(path)
        if not (os.path.exists(raw) and os.path.getsize(raw) > 1500):
            return key, 'FAIL ' + r.stdout.decode('utf-8', 'replace')[:300] + r.stderr.decode('utf-8', 'replace')[:200]
    # 去掉首尾静音，统一响度，转 44.1k mp3
    af = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02,areverse,'
          'silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.06,areverse,'
          'loudnorm=I=-14:TP=-1.0:LRA=7')
    r = subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', raw, '-af', af, '-ar', '44100', '-ac', '1', '-b:a', '128k', dst], capture_output=True)
    if r.returncode != 0 or not os.path.exists(dst):
        return key, 'FFMPEG FAIL ' + r.stderr.decode('utf-8', 'replace')[:300]
    return key, 'ok'


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    keys = sys.argv[1:] or list(LINES)
    ok = 0
    bad = []
    with ThreadPoolExecutor(8) as ex:
        for k, st in ex.map(generate, keys):
            if st in ('ok', 'cached'):
                ok += 1
            else:
                bad.append((k, st))
    print('total %d, ok %d, failed %d' % (len(keys), ok, len(bad)))
    for k, st in bad:
        print('  ', k, st)
    json.dump(LINES, open(os.path.join(OUT, 'lines.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
