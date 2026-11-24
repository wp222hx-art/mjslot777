# -*- coding: utf-8 -*-
"""程序合成全部音效 (16bit 44.1k wav)。运行: python tools/make_sfx.py"""
import os, wave, numpy as np
SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'audio', 'sfx')
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)

class S(np.ndarray):
    """长度不等的波形：相加按最长补零，相乘按最短截断。"""
    def _pair(self, o):
        a = np.asarray(self); b = np.asarray(o)
        return a, b
    def __add__(self, o):
        a, b = self._pair(o)
        if b.ndim == 0: return (a + b).view(S)
        n = max(len(a), len(b)); out = np.zeros(n); out[:len(a)] += a; out[:len(b)] += b
        return out.view(S)
    __radd__ = __add__
    def __mul__(self, o):
        a, b = self._pair(o)
        if b.ndim == 0: return (a * b).view(S)
        n = min(len(a), len(b)); return (a[:n] * b[:n]).view(S)
    __rmul__ = __mul__

def _wrap(fn):
    return lambda *a, **k: np.asarray(fn(*a, **k), dtype=float).view(S)

def t(d): return np.arange(int(SR * d)) / SR
def env(d, a=0.003, k=6.0):
    x = t(d); return np.minimum(x / a, 1.0) * np.exp(-k * x)
def sine(f, d, k=6.0, a=0.003, ph=0.0): return np.sin(2 * np.pi * f * t(d) + ph) * env(d, a, k)
def bell(f, d, k=4.0):
    return sum(sine(f * m, d, k * (1 + i * 0.6)) * g for i, (m, g) in enumerate([(1, 1), (2.01, .5), (2.99, .28), (4.2, .16), (5.4, .08)]))
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def lp(x, c):
    a = np.exp(-2 * np.pi * c / SR); y = np.zeros_like(x); p = 0.0
    for i in range(len(x)):
        p = (1 - a) * x[i] + a * p; y[i] = p
    return y
def hp(x, c): return x - lp(x, c)
def pluck(f, d, damp=0.996):
    n = int(SR / f); buf = rng.uniform(-1, 1, n); out = np.zeros(int(SR * d))
    for i in range(len(out)):
        out[i] = buf[i % n]; buf[i % n] = damp * 0.5 * (buf[i % n] + buf[(i + 1) % n])
    return out
def mix(*parts):
    n = max(len(o) + int(SR * at) for at, o in parts); out = np.zeros(n)
    for at, o in parts:
        s = int(SR * at); out[s:s + len(o)] += np.asarray(o)
    return out.view(S)
def sweep(f0, f1, d, k=3.0):
    x = t(d); f = f0 * (f1 / f0) ** (x / d); return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(d, 0.01, k)
def save(name, x, gain=0.85):
    x = np.array(x, dtype=float)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    n = min(len(x), int(SR * 0.004)); x[-n:] *= np.linspace(1, 0, n)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype('<i2').tobytes())

for _n in ['env', 'sine', 'bell', 'noise', 'lp', 'hp', 'pluck', 'sweep']:
    globals()[_n] = _wrap(globals()[_n])

P = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.5, 1568.0]  # 五声音阶 C D E G A
def clack(f=1900, d=0.09):
    return hp(noise(d), 1500) * env(d, 0.0005, 70) * 0.8 + sine(f, d, 55) * 0.6 + sine(f * 0.47, d, 40) * 0.5

save('click', mix((0, sine(1200, 0.06, 60)), (0, hp(noise(0.03), 3000) * env(0.03, 0.0005, 120) * 0.4)), 0.5)
save('spin', mix((0, lp(noise(0.55), 2200) * np.sin(np.pi * t(0.55) / 0.55) ** 2 * 0.7), (0, sweep(180, 520, 0.5, 2.5) * 0.35),
                 *[(0.05 + i * 0.045, clack(1500 + i * 40, 0.05) * 0.25) for i in range(10)]))
save('reel_stop', mix((0, clack(1400, 0.1)), (0, sine(140, 0.16, 28) * 0.9)))
save('clack', mix((0, clack(2100)), (0.045, clack(1700) * 0.5)))
save('match', mix((0, bell(P[2], 0.5, 7)), (0.06, bell(P[4], 0.5, 7) * 0.8), (0.12, bell(P[5], 0.6, 6) * 0.7), (0, clack(2300) * 0.5)))
save('pop', mix((0, sweep(320, 900, 0.09, 18)), (0, hp(noise(0.05), 2500) * env(0.05, 0.001, 80) * 0.5)), 0.6)
save('wind', mix((0, hp(lp(noise(0.5), 3200), 500) * np.sin(np.pi * t(0.5) / 0.5) ** 1.5), (0.02, sweep(500, 1500, 0.4, 5) * 0.12)), 0.7)
save('slot_in', mix((0, pluck(P[3], 0.6) * env(0.6, 0.002, 4)), (0.0, clack(2000) * 0.7), (0.05, bell(P[6], 0.5, 8) * 0.35)))
save('drop', mix((0, sine(170, 0.12, 30)), (0, clack(1300, 0.07) * 0.5)), 0.6)
save('ting', mix((0, bell(1568, 1.3, 2.6)), (0.0, bell(2349, 1.1, 3.2) * 0.5),
                 *[(0.04 + i * 0.035, hp(noise(0.03), 5000) * env(0.03, 0.0005, 110) * (0.5 - i * 0.04)) for i in range(9)],
                 (0.25, sweep(3200, 5200, 0.6, 5) * 0.12)))
th = lp(noise(1.6), 160) * env(1.6, 0.01, 2.2) * 3
save('thunder', mix((0.05, th), (0, hp(noise(0.12), 2200) * env(0.12, 0.0005, 30)), (0.0, sine(55, 1.2, 3) * 0.8),
                    (0.18, hp(noise(0.25), 1800) * env(0.25, 0.001, 14) * 0.6), (0.3, bell(P[0] / 2, 1.2, 3) * 0.3)))
gong = sum(sine(f, 2.6, 1.5 + i * 0.4) * g for i, (f, g) in enumerate([(98, 1), (147, .7), (196.5, .6), (262, .4), (331, .3), (415, .2)]))
fan = [(0.00, P[0]), (0.11, P[2]), (0.22, P[3]), (0.33, P[5]), (0.50, P[4]), (0.61, P[5]), (0.78, P[7]), (1.0, P[8])]
save('hu', mix((0, gong), (0, lp(noise(0.5), 900) * env(0.5, 0.001, 9) * 1.2), (0, sine(60, 0.6, 7) * 1.2),
               *[(0.25 + at, (pluck(f, 0.9) * env(0.9, 0.002, 2.5) + bell(f, 0.9, 4) * 0.5) * 0.55) for at, f in fan],
               (1.3, sum(bell(f, 1.6, 2.2) for f in (P[5], P[7], P[8])) * 0.3)))
save('hu_symbol', mix((0, sine(82, 0.5, 9) * 1.3), (0, lp(noise(0.25), 700) * env(0.25, 0.001, 16)), (0, bell(P[0], 0.7, 5) * 0.4), (0.0, clack(1200) * 0.4)))
save('invalid', mix((0, sine(196, 0.35, 9)), (0.12, sine(155, 0.4, 8) * 0.9)), 0.5)
save('coin', mix((0, bell(1976, 0.12, 30)), (0.03, bell(2637, 0.14, 26) * 0.7)), 0.45)
save('count_end', mix((0, bell(P[5], 0.9, 4)), (0.0, bell(P[7], 0.9, 4) * 0.7), (0.0, bell(P[8], 0.9, 4) * 0.5)))
save('zhan', mix((0, hp(noise(0.28), 1800) * np.exp(-((t(0.28) - 0.08) / 0.05) ** 2) * 1.2), (0.03, sweep(4200, 500, 0.22, 9) * 0.5),
                 (0.16, sine(70, 0.5, 8) * 1.3), (0.16, lp(noise(0.3), 500) * env(0.3, 0.001, 12)), (0.2, bell(2093, 0.9, 4) * 0.25)))
save('diamond', mix(*[(i * 0.07, bell(f * 2, 0.7, 5) * (0.6 - i * 0.03)) for i, f in enumerate([P[0], P[2], P[3], P[5], P[4], P[7], P[8]])],
                    (0.5, sum(bell(f * 2, 1.6, 2) for f in (P[5], P[7], P[8])) * 0.3),
                    *[(0.1 + i * 0.09, hp(noise(0.02), 7000) * env(0.02, 0.0005, 150) * 0.25) for i in range(12)]))
save('flower', mix(*[(i * 0.055, pluck(f, 0.7) * env(0.7, 0.002, 3) * 0.7 + bell(f * 2, 0.5, 7) * 0.2) for i, f in enumerate([P[5], P[4], P[3], P[2], P[3], P[5], P[7]])]))
save('wild', mix((0, sweep(400, 1600, 0.25, 6) * 0.5), (0.05, bell(P[4], 0.6, 5)), (0.12, bell(P[7], 0.6, 5) * 0.7)))
save('story', mix(*[(i * 0.05, pluck(f, 1.2) * env(1.2, 0.002, 2) * 0.8) for i, f in enumerate([P[0] / 2, P[2] / 2, P[3] / 2, P[4] / 2, P[0], P[2], P[3], P[4], P[5], P[7]])]))
save('levelup', mix(*[(i * 0.09, (bell(f, 0.8, 4) + pluck(f, 0.8) * 0.5) * 0.7) for i, f in enumerate([P[0], P[3], P[5], P[7], P[8]])]))
save('big_win', mix((0, gong * 1.2), (0, sine(50, 1.0, 4) * 1.4),
                    *[(0.2 + i * 0.1, (pluck(f, 1.2) * env(1.2, 0.002, 2) + bell(f, 1.0, 3) * 0.6) * 0.5) for i, f in enumerate([P[0], P[2], P[3], P[4], P[5], P[4], P[5], P[7], P[8], P[7], P[8], P[8] * 1.125 * 1.0])],
                    (1.5, sum(bell(f, 2.4, 1.5) for f in (P[3], P[5], P[7], P[8])) * 0.35)))
save('fire', mix((0, lp(noise(1.4), 1400) * (0.5 + 0.5 * np.abs(lp(noise(1.4), 12)) * 8).clip(0, 2) * np.sin(np.pi * t(1.4) / 1.4) ** 0.6),
                 *[(rng.uniform(0, 1.2), hp(noise(0.015), 3000) * env(0.015, 0.0005, 200) * 0.5) for _ in range(30)]), 0.6)
save('tick', mix((0, sine(2400, 0.025, 120) * 0.6), (0, hp(noise(0.012), 4000) * env(0.012, 0.0005, 200) * 0.4)), 0.35)
print(sorted(os.listdir(OUT)))
