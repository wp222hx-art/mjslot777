# -*- coding: utf-8 -*-
"""讲解视频合成：录好的游戏画面 + 解说语音 + 字幕 -> mp4。
  1) 录画面（约 2 分钟，窗口保持在前台）：
     godot --path . --write-movie <FILM>/raw.avi --fixed-fps 60 --resolution 1080x1920 -- film > <FILM>/film.log
     ffmpeg -i raw.avi -c:v libx264 -crf 16 -pix_fmt yuv420p -c:a pcm_s16le mid.mov
  2) python tools/make_film.py tts    生成解说语音（有缓存）
  3) python tools/make_film.py mix    按 film.log 里的 MARK 时间点对位，合成成片
解说每句挂在一个 MARK 上（段落名 + 偏移秒），画面流程改了也不用重新掐时间。
"""
import json, os, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILM = os.path.join(os.environ.get('TEMP', tempfile.gettempdir()), 'gencode', 'film')
VO = os.path.join(ROOT, 'tools', 'vo_src', 'film')
OUT = os.path.join(os.path.dirname(ROOT), '麻将转运胡_讲解视频.mp4')
VOICE = 'Charon'
STYLE = ('young Chinese male game trailer narrator, Mandarin, clear and confident, upbeat and fast-paced, '
         'explaining the rules with excitement, no pauses between phrases')

# (编号, 挂靠的 MARK, 偏移秒, 朗读文本, 字幕（\\N 换行）)
LINES = [
    ('n01', 'intro', 0.3, '麻将转运胡，把麻将做成了老虎机！', '麻将转运胡，把麻将做成了老虎机！'),
    ('n02', 'spin1_landed', 0.2, '每转扣一次投注。三张相连就消除，需要的牌飞进手牌，连消越多，赢得越多。',
     '每转扣一次投注。三张相连就消除，\\N需要的牌飞进手牌，连消越多赢得越多。'),
    ('n03', 'bonus', 0.2, '风牌集齐，长卷横穿！越快集齐，奖越高。', '风牌集齐，长卷横穿！越快集齐，奖越高。'),
    ('n04', 'story', 0.3, '短剧情二选一：拿一张黄金牌，还是拿斩杀技能。', '短剧情二选一：\\N拿一张黄金牌，还是拿「斩」技能。'),
    ('n05', 'spin3', 1.3, '凑成刻子喊碰！只差最后一张，听牌！', '凑成刻子喊「碰」！只差最后一张，听牌！'),
    ('n06', 'zhan', 0.1, '用斩补上最后一张，成牌待胡！', '用「斩」补上最后一张，成牌待胡！'),
    ('n07', 'spin4', 0.3, '再消出胡字，才算胡牌！', '再消出「胡」字，才算胡牌！'),
    ('n08', 'settle', 0.5, '胡牌赔率，等于投注乘任务系数，再乘品级系数。大奖送免费转，钻石局还能再抽一次。',
     '胡牌赔率 = 投注 × 任务系数 × 品级系数。\\N大奖送免费转，钻石局还能再抽一次。'),
    ('n09', 'bighand', 0.3, '攒满大牌副线，十三幺亮相，还送免费转！', '攒满大牌副线，十三幺亮相，还送免费转！'),
    ('n10', 'end', 0.15, '转出好牌，胡个痛快！', '转出好牌，胡个痛快！'),
]


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)


def dur(path):
    r = run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path])
    return float(r.stdout.decode().strip() or 0)


def tts(item):
    key, _mark, _off, text, _sub = item
    raw = os.path.join(VO, key + '.raw')
    wav = os.path.join(VO, key + '.wav')
    stamp = os.path.join(VO, key + '.txt')
    if os.path.exists(wav) and os.path.exists(stamp) and open(stamp, encoding='utf-8').read() == text:
        return key, 'cached'
    args = {'prompt': text, 'model': 'google/gemini-3.8-flash-tts', 'audio_type': 'speech', 'file_name': key,
            'params': {'speakers': [{'speaker': 'Speaker1', 'voice_name': VOICE}], 'instructions': STYLE}}
    with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8') as f:
        json.dump(args, f, ensure_ascii=False)
        path = f.name
    try:
        if os.path.exists(raw):
            os.remove(raw)
        for _attempt in range(2):
            r = subprocess.run('gsk audio_generation --args-file "%s" -o "%s"' % (path, raw), shell=True, capture_output=True)
            if os.path.exists(raw) and os.path.getsize(raw) > 1500:
                break
    finally:
        os.unlink(path)
    if not (os.path.exists(raw) and os.path.getsize(raw) > 1500):
        return key, 'FAIL ' + r.stdout.decode('utf-8', 'replace')[:300] + r.stderr.decode('utf-8', 'replace')[:200]
    af = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02,areverse,'
          'silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse,'
          'loudnorm=I=-15:TP=-1.5:LRA=7')
    r = run(['ffmpeg', '-y', '-v', 'error', '-i', raw, '-af', af, '-ar', '48000', '-ac', '2', wav])
    if r.returncode != 0:
        return key, 'FFMPEG FAIL ' + r.stderr.decode('utf-8', 'replace')[:300]
    open(stamp, 'w', encoding='utf-8').write(text)
    return key, 'ok %.2fs' % dur(wav)


def marks():
    """读 film.log 的段落时间点；录制不完整（没跑完、中途停画、超时）时返回 None。"""
    m = {}
    ok = True
    text = open(os.path.join(FILM, 'film.log'), encoding='utf-8', errors='replace').read()
    for line in text.splitlines():
        g = re.match(r'MARK (\w+) ([\d.]+) frames=(\d+) drawn=(\d+)', line.strip())
        if g:
            m[g.group(1)] = float(g.group(2))
            if g.group(3) != g.group(4):
                ok = False
                print('!! 段落 %s 逻辑帧 %s ≠ 已绘制帧 %s：录制中途停过画，这段录像不能用' % (g.group(1), g.group(3), g.group(4)))
    for bad in ['PHASE_TIMEOUT', 'PRESS_MISS', 'WM_CLOSE', 'SCRIPT ERROR']:
        if bad in text:
            ok = False
            print('!! film.log 里有 %s，这段录像不能用' % bad)
    if 'FILM_DONE' not in text:
        ok = False
        print('!! film.log 里没有 FILM_DONE，录制没跑完')
    return m if ok else None


def ass_time(t):
    return '%d:%02d:%05.2f' % (int(t // 3600), int(t % 3600 // 60), t % 60)


def mix():
    mk = marks()
    if mk is None:
        return 1
    src = os.path.join(FILM, 'mid.mov')
    total = dur(src)
    plan = []
    for key, mark, off, _text, sub in LINES:
        if mark not in mk:
            print('!! film.log 里没有段落', mark)
            return 1
        wav = os.path.join(VO, key + '.wav')
        plan.append({'key': key, 'wav': wav, 'start': mk[mark] + off, 'len': dur(wav), 'sub': sub, 'tempo': 1.0})
    # 一句话不能压到下一句（或片尾）上：超出就略微加速，实在放不下就报出来
    bad = 0
    for i, p in enumerate(plan):
        limit = (plan[i + 1]['start'] if i + 1 < len(plan) else total) - 0.12
        room = limit - p['start']
        if p['len'] > room:
            p['tempo'] = p['len'] / room
            if p['tempo'] > 1.22:
                bad += 1
                print('!! %s 需要加速 %.2f 倍才放得下（%.2fs 的话只有 %.2fs 空档）' % (p['key'], p['tempo'], p['len'], room))
        p['end'] = p['start'] + p['len'] / p['tempo']
        print('%s  %6.2f → %6.2f  时长 %.2fs  变速 ×%.2f' % (p['key'], p['start'], p['end'], p['len'], p['tempo']))
    if bad:
        return 1

    ass = ['[Script Info]', 'ScriptType: v4.00+', 'PlayResX: 1080', 'PlayResY: 1920', 'WrapStyle: 2', '',
           '[V4+ Styles]',
           'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, '
           'Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
           'Style: cap,Microsoft YaHei,48,&H00D8F3FF,&H00D8F3FF,&H00101820,&H00000000,1,0,0,0,100,100,1,0,1,3,0,5,30,30,0,1', '',
           '[Events]', 'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text']
    for p in plan:
        # \an5 + \pos：字幕中心固定在底部解说条的正中
        ass.append('Dialogue: 0,%s,%s,cap,,0,0,0,,{\\an5\\pos(540,1824)\\fad(120,120)}%s' % (ass_time(p['start'] - 0.05), ass_time(p['end'] + 0.25), p['sub']))
    open(os.path.join(FILM, 'sub.ass'), 'w', encoding='utf-8-sig').write('\n'.join(ass) + '\n')

    # 第一步：只混音。解说按时间点铺开，解说响起时把游戏声压下去，说完再放开
    cmd = ['ffmpeg', '-y', '-v', 'error', '-nostats', '-i', 'mid.mov']
    fc = []
    for i, p in enumerate(plan):
        cmd += ['-i', p['wav']]
        chain = ('atempo=%.4f,' % p['tempo']) if p['tempo'] > 1.001 else ''
        fc.append('[%d:a]%sadelay=%d:all=1[n%d]' % (i + 1, chain, int(round(p['start'] * 1000)), i))
    n = len(plan)
    fc.append(''.join('[n%d]' % i for i in range(n)) + 'amix=inputs=%d:normalize=0:dropout_transition=0,apad=whole_dur=%.3f,asplit=2[nv][nk]' % (n, total))
    fc.append('[0:a]volume=0.8[g0];[g0][nk]sidechaincompress=threshold=0.02:ratio=10:attack=15:release=450:makeup=1[g1]')
    fc.append('[g1][nv]amix=inputs=2:normalize=0:dropout_transition=0,alimiter=limit=0.95,afade=t=out:st=%.2f:d=0.5[a]' % (total - 0.5))
    r = run(cmd + ['-filter_complex', ';'.join(fc), '-map', '[a]', '-t', '%.3f' % total, '-c:a', 'pcm_s16le', 'mix.wav'], cwd=FILM)
    print('PASS audio rc=%d %s' % (r.returncode, r.stderr.decode('utf-8', 'replace')[-800:]))
    if r.returncode != 0:
        return 1
    # 第二步：画面缩到 90% 靠上，底部留一条 192 像素的解说条放字幕，再配上混好的音轨
    vf = ('scale=972:1728:flags=lanczos,pad=1080:1920:54:0:color=0x0b1f18,'
          'drawbox=x=0:y=1728:w=1080:h=192:color=0x120b06:t=fill,drawbox=x=0:y=1728:w=1080:h=4:color=0xb88a3e:t=fill,'
          'subtitles=sub.ass,fade=t=out:st=%.2f:d=0.4' % (total - 0.4))
    out = os.path.join(FILM, 'out.mp4')
    # 这台机器上压制不稳定：medium 预设会崩（非法指令），veryfast 也出过坏帧。
    # 所以每次压完都整段解码校验，有任何解码错误就重压；连续失败则不出片。
    good = False
    for attempt in range(1, 5):
        r = run(['ffmpeg', '-y', '-v', 'error', '-nostats', '-i', 'mid.mov', '-i', 'mix.wav', '-map', '0:v', '-map', '1:a', '-vf', vf,
                 '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18', '-pix_fmt', 'yuv420p', '-r', '60', '-threads', '4',
                 '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', 'out.mp4'], cwd=FILM)
        print('PASS video #%d rc=%d %s' % (attempt, r.returncode, r.stderr.decode('utf-8', 'replace')[-800:]))
        if r.returncode != 0:
            continue
        v = run(['ffmpeg', '-v', 'error', '-nostats', '-i', 'out.mp4', '-f', 'null', '-'], cwd=FILM)
        errs = v.stderr.decode('utf-8', 'replace').strip()
        print('VERIFY #%d rc=%d 解码报错 %d 行 %s' % (attempt, v.returncode, len(errs.splitlines()), errs[:300]))
        if v.returncode == 0 and errs == '':
            good = True
            break
    if not good:
        if os.path.exists(out):
            os.remove(out)  # 不留损坏的成品
        print('!! 连续 4 次都没压出干净的文件，未出片')
        return 1
    import shutil
    shutil.copyfile(out, OUT)
    print('OUT', OUT, '%.2fs' % dur(OUT), '%.1f MB' % (os.path.getsize(OUT) / 1e6))
    return 0


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    os.makedirs(VO, exist_ok=True)
    step = sys.argv[1] if len(sys.argv) > 1 else 'tts'
    if step == 'tts':
        fail = 0
        with ThreadPoolExecutor(5) as ex:
            for k, st in ex.map(tts, LINES):
                print(k, st)
                fail += st.startswith('F')
        sys.exit(1 if fail else 0)
    sys.exit(mix())
