"""用代码合成的短音效（不用外部素材）。只用 Python 标准库。

    python tools/make_sfx.py

生成到 assets/audio/sfx/：
  starter.wav   S-01 起动机：电机的嗡鸣，音高持续上升，叠着压缩冲程的"突突"脉动（1.6 秒）
  ui_move.wav   S-30 菜单移动：短促的高音"嘀"
  ui_ok.wav     S-31 确定：两个上行的音
  ui_back.wav   S-32 返回：一个下行的音
  comm.wav      S-33 字幕出现：无线电的"哔"声加一点噪声
  shift.wav     换挡：变速箱的"咔哒"
  pop.wav       回火：短促的爆裂
  sticker.wav   S-24 贴纸出现：上扬的"叮"
  shine.wav     S-25 高光扫过：轻的上扫
  whiteout.wav  S-27 终点白化：长的上扬亮音
  pass.wav      S-09 高速穿过门、拱门、龙门架：短促的"呼"
  star_warp.wav S-08 进入星速：被吸进去的低沉轰鸣 + 高频上扬（python tools/make_sfx.py warp）
  record.wav    刷新纪录的琶音（python tools/make_sfx.py record）
  rumble.wav    擦护栏预警：路肩的"突突突"，1 秒循环（python tools/make_sfx.py rumble）
  corner_perfect.wav / corner_great.wav  过弯评价的铃声（只生成这两个：python tools/make_sfx.py corner）
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.89 / peak
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))


def env(i, n, attack=0.005, release=0.05):
    t = i / RATE
    total = n / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (total - t) / release) if release > 0 else 1.0
    return max(0.0, a * r)


def tone(freq_fn, dur, shape="sine", amp_fn=None, attack=0.005, release=0.05, noise=0.0, seed=1):
    rnd = random.Random(seed)
    n = int(dur * RATE)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        f = freq_fn(t)
        ph += f / RATE
        x = ph % 1.0
        if shape == "sine":
            v = math.sin(2 * math.pi * x)
        elif shape == "saw":
            v = 2 * x - 1
        elif shape == "square":
            v = 1.0 if x < 0.5 else -1.0
        else:
            v = 1 - 4 * abs(x - 0.5)
        if noise:
            v = v * (1 - noise) + (rnd.random() * 2 - 1) * noise
        a = amp_fn(t) if amp_fn else 1.0
        out.append(v * a * env(i, n, attack, release))
    return out


def lowpass(samples, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    k = (1.0 / RATE) / (rc + 1.0 / RATE)
    y = 0.0
    out = []
    for s in samples:
        y += k * (s - y)
        out.append(y)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def starter():
    dur = 1.6
    # 电机嗡鸣：锯齿波，音高从 110 Hz 升到 260 Hz；"突突"脉动从 7 Hz 升到 13 Hz
    def f(t):
        return 110 + 150 * (t / dur) ** 1.3

    def chug_rate(t):
        return 7 + 6 * t / dur

    ph = [0.0]
    last = [0.0]

    def amp(t):
        dt = t - last[0]
        last[0] = t
        ph[0] += chug_rate(t) * dt
        x = ph[0] % 1.0
        return 0.45 + 0.55 * (math.sin(math.pi * x) ** 6)

    motor = tone(f, dur, "saw", amp, attack=0.02, release=0.08, noise=0.12, seed=3)
    whine = tone(lambda t: f(t) * 4.0, dur, "sine", lambda t: 0.25, attack=0.05, release=0.08)
    return lowpass(mix(motor, whine), 2600)


def blip(f0, f1, dur, shape="square", vol=1.0):
    return [s * vol for s in tone(lambda t: f0 + (f1 - f0) * t / dur, dur, shape, attack=0.002, release=dur * 0.6)]


def concat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def silence(dur):
    return [0.0] * int(dur * RATE)


def shift_clunk():
    rnd = random.Random(7)
    n = int(0.09 * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        click = (rnd.random() * 2 - 1) * math.exp(-t * 90)
        body = math.sin(2 * math.pi * 180 * t) * math.exp(-t * 45) * 0.6
        out.append(click + body)
    return lowpass(out, 3500)


def backfire_pop():
    rnd = random.Random(11)
    n = int(0.22 * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        crack = (rnd.random() * 2 - 1) * math.exp(-t * 55)
        thump = math.sin(2 * math.pi * (70 - 30 * t / 0.22) * t) * math.exp(-t * 18) * 0.9
        out.append(crack * 0.8 + thump)
    return lowpass(out, 2200)


def main():
    write("starter.wav", starter())
    write("ui_move.wav", blip(880, 990, 0.05))
    write("ui_ok.wav", concat(blip(660, 660, 0.06), blip(990, 990, 0.09)))
    write("ui_back.wav", blip(660, 440, 0.09))
    comm = mix(blip(1320, 1320, 0.08, "sine"), [s * 0.15 for s in tone(lambda t: 1000, 0.12, "sine", noise=1.0, seed=5)])
    write("comm.wav", comm)
    write("shift.wav", shift_clunk())
    write("pop.wav", backfire_pop())
    write("sticker.wav", concat(blip(1046, 1046, 0.07, "triangle"), blip(1568, 1568, 0.25, "triangle")))
    write("shine.wav", [s * 0.5 for s in tone(lambda t: 1800 + 2400 * t / 0.35, 0.35, "sine", attack=0.05, release=0.2)])
    write("whiteout.wav", mix(tone(lambda t: 220 + 660 * (t / 1.0) ** 2, 1.0, "triangle", attack=0.1, release=0.15),
                              [s * 0.4 for s in tone(lambda t: 440 + 1320 * (t / 1.0) ** 2, 1.0, "sine", attack=0.1, release=0.15)]))


def corner_chimes():
    """过弯评价（开发者 2026-11-19 第 1 轮 #6）：完美 = 三个音上行的亮铃声；漂亮 = 两个音、轻一些。"""
    write("corner_perfect.wav", concat(blip(1318, 1318, 0.05, "triangle", 0.8), blip(1568, 1568, 0.05, "triangle", 0.8),
                                       blip(2093, 2093, 0.22, "triangle", 0.8)))
    write("corner_great.wav", concat(blip(1175, 1175, 0.05, "triangle", 0.5), blip(1568, 1568, 0.16, "triangle", 0.5)))


def star_warp():
    """S-08 进入星速（规格 10.3）：一声被吸进去的低沉轰鸣 + 高频上扬，1.0 秒。
    低频：60 → 32 Hz 的正弦，先吸进来（音量 0.15 秒内涨满）再衰减；中间一层反向包络的噪声（越来越大，最后突然收住）；
    高频：1.5 → 7 kHz 的上扬扫频。"""
    rnd = random.Random(808)
    n = RATE
    out = []
    ph_lo = 0.0
    ph_hi = 0.0
    noise_y = 0.0
    for i in range(n):
        t = i / RATE
        f_lo = 60 - 28 * t
        ph_lo += f_lo / RATE
        lo = math.sin(2 * math.pi * ph_lo) * min(1.0, t / 0.15) * math.exp(-max(0.0, t - 0.15) * 3.5)
        f_hi = 1500 + 5500 * t ** 1.5
        ph_hi += f_hi / RATE
        hi = math.sin(2 * math.pi * ph_hi) * 0.18 * math.sin(math.pi * t) ** 2
        noise_y += 0.25 * ((rnd.random() * 2 - 1) - noise_y)
        swell = noise_y * 0.5 * (t / 0.55) ** 2 if t < 0.55 else noise_y * 0.5 * math.exp(-(t - 0.55) * 18)
        out.append(lo * 0.9 + hi + swell)
    return out


def record_fanfare():
    """刷新纪录（开发者 2026-11-19 第 3 轮 #4）：大三和弦琶音上行 + 最后一个长音。"""
    notes = [(784, 0.07), (988, 0.07), (1175, 0.07), (1568, 0.35)]
    return concat(*[blip(f, f, d, "triangle", 0.8) for f, d in notes])


def rumble():
    """擦护栏预警（开发者 2026-11-19 第 3 轮 #2）：路肩的震动"突突突"，1 秒正好 24 下，首尾相接无缝循环。
    游戏里按车速改音调（越快越密）。"""
    rnd = random.Random(31)
    n = RATE
    out = [0.0] * n
    per = n // 24
    for k in range(24):
        for i in range(per):
            t = i / RATE
            env = math.exp(-t * 90)
            out[k * per + i] = (math.sin(2 * math.pi * 62 * t) * 0.8 + (rnd.random() * 2 - 1) * 0.35) * env
    return lowpass(out, 900)


def passby():
    rnd = random.Random(13)
    dur = 0.35
    n = int(dur * RATE)
    out = []
    y = 0.0
    for i in range(n):
        t = i / RATE
        cutoff = 600 + 5000 * math.sin(math.pi * t / dur)
        rc = 1.0 / (2 * math.pi * cutoff)
        k = (1.0 / RATE) / (rc + 1.0 / RATE)
        y += k * ((rnd.random() * 2 - 1) - y)
        out.append(y * math.sin(math.pi * t / dur) ** 1.5)
    return out


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["corner"]:
        corner_chimes()
    elif sys.argv[1:] == ["rumble"]:
        write("rumble.wav", rumble())
    elif sys.argv[1:] == ["record"]:
        write("record.wav", record_fanfare())
        write("star_warp.wav", star_warp())
    elif sys.argv[1:] == ["warp"]:
        write("star_warp.wav", star_warp())
    else:
        write("pass.wav", passby())
        main()
        corner_chimes()
        write("rumble.wav", rumble())
        write("record.wav", record_fanfare())
        write("star_warp.wav", star_warp())
