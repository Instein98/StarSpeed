"""用代码合成两首临时音乐（规格 10.2）。开发者同意下载正式素材之前用它们顶上。

    python tools/make_music.py

需要 numpy 和 ffmpeg（输出 OGG Vorbis）。所有延迟和混响都按"循环"计算（首尾相接），所以导出的文件无缝循环。
  assets/audio/music/star_base/drums/lead.ogg  M-01 星速：172 BPM 的鼓打贝斯，明亮的合成器主音，无人声，约 67 秒；
                                  分底轨、鼓、主音三轨，游戏里按跑得好不好逐层叠加（music.gd）
  assets/audio/music/ambient.ogg  M-02 氛围：安静的合成器长音铺底，无节拍，空旷的回响，96 秒
  assets/audio/world/wind.ogg     S-14 风声：偏高频的白噪，4 秒循环
只生成其中几个：python tools/make_music.py wind
"""
import os
import subprocess
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "music")
rng = np.random.default_rng(172)


def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def osc(freq, n, shape="saw", phase=0.0):
    t = np.arange(n) / RATE
    x = (phase + freq * t) % 1.0
    if shape == "saw":
        return 2.0 * x - 1.0
    if shape == "square":
        return np.where(x < 0.5, 1.0, -1.0)
    if shape == "tri":
        return 1.0 - 4.0 * np.abs(x - 0.5)
    return np.sin(2 * np.pi * x)


def adsr(n, a, d, s, r):
    env = np.ones(n) * s
    ia, idd, ir = int(a * RATE), int(d * RATE), int(r * RATE)
    ia = min(ia, n)
    env[:ia] = np.linspace(0, 1, ia, endpoint=False)
    end_d = min(ia + idd, n)
    env[ia:end_d] = np.linspace(1, s, end_d - ia, endpoint=False)
    if ir > 0:
        ir = min(ir, n)
        env[n - ir:] *= np.linspace(1, 0, ir)
    return env


def lowpass(x, cutoff, slope=2.0):
    """FFT 上的平滑低通（循环）。"""
    spec = np.fft.rfft(x, axis=0)
    f = np.fft.rfftfreq(x.shape[0], 1.0 / RATE)
    gain = 1.0 / (1.0 + (f / cutoff) ** (2 * slope))
    if x.ndim == 2:
        gain = gain[:, None]
    return np.fft.irfft(spec * gain, n=x.shape[0], axis=0)


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def reverb(x, seconds, mix, seed=1):
    """循环卷积一段指数衰减的噪声（立体声左右不同），尾巴自然绕回开头。"""
    r = np.random.default_rng(seed)
    n = x.shape[0]
    m = int(seconds * RATE)
    out = np.zeros((n, 2))
    for ch in range(2):
        ir = np.zeros(n)
        tail = r.standard_normal(m) * np.exp(-np.arange(m) / (m / 6.0))
        ir[:m] = lowpass(tail, 6000) * 0.02
        src = x[:, ch] if x.ndim == 2 else x
        out[:, ch] = np.fft.irfft(np.fft.rfft(src) * np.fft.rfft(ir), n=n)
    dry = x if x.ndim == 2 else np.stack([x, x], axis=1)
    return dry * (1 - mix) + out * mix * 4.0


def delay(x, seconds, feedback, mix, repeats=5):
    out = x.copy()
    d = int(seconds * RATE)
    g = 1.0
    for k in range(1, repeats + 1):
        g *= feedback
        shifted = np.roll(x, d * k, axis=0)
        if x.ndim == 2 and k % 2 == 1:
            shifted = shifted[:, ::-1]      # 乒乓
        out += shifted * g * mix
    return out


def place(buf, sound, start):
    """把 sound 加到 buf 的 start 位置；超出结尾的部分绕回开头（循环）。"""
    n = buf.shape[0]
    start %= n
    end = start + sound.shape[0]
    if end <= n:
        buf[start:end] += sound
    else:
        cut = n - start
        buf[start:] += sound[:cut]
        buf[:end - n] += sound[cut:]


def stereo(x, pan=0.0):
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    return np.stack([x * l, x * r], axis=1)


def save(name, buf, peak=0.89):
    """peak 为 None 时不归一化（分轨要共用一个增益）。"""
    if peak is not None:
        buf = buf / max(1e-9, np.max(np.abs(buf))) * peak
    os.makedirs(OUT, exist_ok=True)
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((buf * 32767).astype("<i2").tobytes())
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
    os.remove(wav)
    print("wrote", ogg)


# ───────────────────────── M-01 星速 ─────────────────────────

def drums_kick():
    n = int(0.35 * RATE)
    t = np.arange(n) / RATE
    f = 45 + 110 * np.exp(-t * 35)
    ph = np.cumsum(f) / RATE
    body = np.sin(2 * np.pi * ph) * np.exp(-t * 9)
    click = rng.standard_normal(n) * np.exp(-t * 300) * 0.4
    return body + click


def drums_snare():
    n = int(0.3 * RATE)
    t = np.arange(n) / RATE
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.6
    noise = highpass(rng.standard_normal(n), 1200) * np.exp(-t * 14)
    return tone + noise * 0.9


def drums_hat(open_=False):
    n = int((0.18 if open_ else 0.05) * RATE)
    t = np.arange(n) / RATE
    noise = highpass(rng.standard_normal(n), 7000)
    return noise * np.exp(-t * (18 if open_ else 80)) * 0.35


# 三个区段各一首（开发者 2026-11-19 第 3 轮 #6）：同样的速度、长度和结构，换调、和弦、主音的音色和走法。
VARIANTS = {
    # 森林：A 小调 Am F C G，方波 + 锯齿的明亮主音（原来那首）
    "star": dict(prog=[(57, [0, 3, 7]), (53, [0, 4, 7]), (60, [0, 4, 7]), (55, [0, 4, 7])],
                 lead=("square", "saw"), lead_cut=5200, lead_oct=12, sparse=False, verb=0.18, seed=172),
    # 冰原：D 小调 Dm B♭ F C，三角波 + 正弦的冷亮主音，八分音符更稀，混响更大
    "star_ice": dict(prog=[(62, [0, 3, 7]), (58, [0, 4, 7]), (65, [0, 4, 7]), (60, [0, 4, 7])],
                     lead=("tri", "sine"), lead_cut=7000, lead_oct=12, sparse=True, verb=0.32, seed=273),
    # 城市：E 小调 Em C G D，双锯齿的硬朗主音，低八度更有力
    "star_city": dict(prog=[(52, [0, 3, 7]), (48, [0, 4, 7]), (55, [0, 4, 7]), (50, [0, 4, 7])],
                      lead=("saw", "saw"), lead_cut=4200, lead_oct=12, sparse=False, verb=0.12, seed=374),
}


def star_all():
    for name in VARIANTS:
        star(name)


def star(name="star"):
    cfg = VARIANTS[name]
    global rng
    rng = np.random.default_rng(cfg["seed"])
    """分三轨导出（开发者 2026-11-16：分层音乐，跟着跑得好不好逐层叠加），三轨等长、同时开始播放：
    star_base  贝斯、铺底和弦、踩镲——计时赛和练习里一直有
    star_drums 底鼓、军鼓、开镲——跑得够快时加入
    star_lead  明亮的主音琶音——跑得接近理想时加入
    三轨用同一个增益归一化，叠在一起就是原来的完整曲子。"""
    bpm = 172.0
    beat = 60.0 / bpm
    bars = 48
    n = int(round(bars * 4 * beat * RATE))
    six = beat / 4.0
    mix = np.zeros((n, 2))     # 鼓轨
    hats = np.zeros((n, 2))    # 踩镲放进底轨，只有底轨时也有律动
    side = np.ones(n)          # 底鼓压缩：贝斯和铺底在底鼓上让位

    kick, snare = drums_kick(), drums_snare()
    hat, ohat = drums_hat(), drums_hat(True)
    for bar in range(bars):
        b0 = bar * 4 * beat
        # 鼓打贝斯的两步节奏：底鼓在 1 和第 2 拍后半的十六分，军鼓在 2、4 拍
        kicks = [0, 10] if bar % 4 != 3 else [0, 10, 14]
        for k in kicks:
            s = int((b0 + k * six) * RATE)
            place(mix, stereo(kick * 0.95), s)
            dur = int(0.22 * RATE)
            idx = (np.arange(dur) + s) % n
            side[idx] = np.minimum(side[idx], 0.35 + 0.65 * np.linspace(0, 1, dur) ** 0.7)
        for k in [4, 12]:
            place(mix, stereo(snare * 0.8), int((b0 + k * six) * RATE))
        if bar % 2 == 1:
            place(mix, stereo(snare * 0.25, 0.2), int((b0 + 15 * six) * RATE))   # 碎的装饰军鼓
        for k in range(16):
            if k % 2 == 0:
                v = 0.5 if k % 4 == 2 else 0.3
                place(hats, stereo(hat * v, -0.3), int((b0 + k * six) * RATE))
            elif rng.random() < 0.35:
                place(hats, stereo(hat * 0.18, 0.3), int((b0 + k * six) * RATE))
        place(mix, stereo(ohat * 0.35, 0.4), int((b0 + 6 * six) * RATE))

    # 和弦进行（A 小调，每两小节换一个）：Am F C G
    prog = cfg["prog"]
    bar_len = 4 * beat
    bass = np.zeros(n)
    pad = np.zeros(n)
    lead = np.zeros(n)
    for bar in range(0, bars, 2):
        root, chord = prog[(bar // 2) % 4]
        s = int(bar * bar_len * RATE)
        m = int(2 * bar_len * RATE)
        # 里斯贝斯：两个失谐锯齿波
        f = midi(root - 24)
        b = osc(f, m, "saw") + osc(f * 1.006, m, "saw", 0.3) + 0.6 * osc(f * 0.5, m, "sine")
        bass_seg = b * adsr(m, 0.01, 0.2, 0.85, 0.05)
        idx = (np.arange(m) + s) % n
        bass[idx] += bass_seg
        # 铺底和弦
        pseg = np.zeros(m)
        for iv in chord:
            for det in (0.997, 1.003):
                pseg += osc(midi(root + iv) * det, m, "saw", rng.random())
        pad[idx] += pseg * adsr(m, 0.15, 0.4, 0.7, 0.2)
        # 明亮的主音：十六分音符的琶音，每 8 小节换一种走法
        pattern_kind = (bar // 8) % 3
        tones = [root + cfg["lead_oct"] + iv for iv in chord] + [root + cfg["lead_oct"] + 12]
        steps = 32
        for k in range(steps):
            if cfg["sparse"] and k % 2 == 1:
                continue                     # 冰原：八分音符
            if pattern_kind == 0:
                note = tones[k % 4]
            elif pattern_kind == 1:
                note = tones[[0, 2, 1, 3, 2, 1, 3, 2][k % 8]] + (12 if k % 16 >= 12 else 0)
            else:
                note = tones[[3, 2, 1, 0][k % 4]] + (12 if (k // 4) % 2 else 0)
            st = s + int(k * six * RATE)
            ln = int(six * 0.9 * RATE)
            f = midi(note)
            if cfg["sparse"]:
                ln = int(six * 1.8 * RATE)
            tone = 0.6 * osc(f, ln, cfg["lead"][0]) + 0.4 * osc(f * 1.005, ln, cfg["lead"][1])
            seg = tone * adsr(ln, 0.003, 0.06, 0.45, 0.02)
            place(lead, seg, st)
    # 底轨单独放时没有底鼓，压缩只留一半，免得听起来在莫名其妙地抽动
    side = 0.5 + 0.5 * side
    bass = lowpass(bass, 380) * side
    pad = lowpass(pad, 2200) * side
    lead = lowpass(lead, cfg["lead_cut"])
    base = hats + stereo(bass * 0.55)
    base += stereo(pad * 0.10, -0.4) * 0.5 + stereo(pad * 0.10, 0.4) * 0.5
    lead_st = delay(stereo(lead * 0.22), beat * 0.75, 0.45, 0.5)
    lead_mix = reverb(lead_st, 1.2, cfg["verb"], seed=3)
    stems = {name + "_base": np.tanh(base * 1.3), name + "_drums": np.tanh(mix * 1.3), name + "_lead": np.tanh(lead_mix * 1.3)}
    gain = 0.89 / max(1e-9, np.max(np.abs(sum(stems.values()))))
    for name, buf in stems.items():
        save(name, buf * gain, None)


# ───────────────────────── M-02 氛围 ─────────────────────────

def ambient():
    total = 96.0
    n = int(total * RATE)
    mix = np.zeros((n, 2))
    # 四个和弦各 24 秒，前后交叠 8 秒：Am9 Fmaj7 Cmaj7 Em7
    chords = [[45, 57, 60, 64, 71], [41, 53, 57, 60, 64], [48, 55, 59, 64, 67], [40, 52, 55, 59, 62]]
    seg = 24.0
    for i, chord in enumerate(chords):
        start = int(i * seg * RATE)
        m = int((seg + 8.0) * RATE)
        env = adsr(m, 7.0, 1.0, 1.0, 8.0)
        for j, note in enumerate(chord):
            f = midi(note)
            # 缓慢起伏的音量，让长音有呼吸
            lfo = 0.75 + 0.25 * np.sin(2 * np.pi * (0.05 + 0.013 * j) * np.arange(m) / RATE + j)
            tone = osc(f, m, "tri", rng.random()) * 0.6 + osc(f * 1.002, m, "sine", rng.random()) * 0.4
            pan = [-0.6, -0.2, 0.2, 0.5, 0.0][j]
            place(mix, stereo(tone * env * lfo * (0.5 if j == 0 else 0.3), pan), start)
    # 高处很轻的闪光音
    for k in range(14):
        t0 = rng.uniform(0, total)
        note = rng.choice([76, 79, 81, 83, 84, 88])
        m = int(3.0 * RATE)
        s = osc(midi(note), m, "sine") * adsr(m, 0.02, 0.5, 0.2, 2.0) * 0.12
        place(mix, stereo(s, rng.uniform(-0.8, 0.8)), int(t0 * RATE))
    mix = lowpass(mix, 3000)
    save("ambient", reverb(mix, 4.5, 0.55, seed=7))


# ───────────────────────── 区段环境声（开发者 2026-11-19 第 4 轮 #4） ─────────────────────────

def _save_world(name, out, peak):
    path = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "world")
    global OUT
    keep = OUT
    OUT = path
    save(name, out, peak)
    OUT = keep


def amb_forest():
    """森林：轻的林间风 + 随机的鸟叫（两种：上扬的啾、快速的颤音），12 秒循环。"""
    n = 12 * RATE
    r = np.random.default_rng(41)
    out = lowpass(highpass(r.standard_normal((n, 2)), 200), 1200) * 0.15
    t_all = np.arange(n) / RATE
    for k in range(18):
        start = int(r.uniform(0, 12) * RATE)
        kind = r.integers(0, 2)
        dur = 0.18 if kind == 0 else 0.35
        m = int(dur * RATE)
        t = np.arange(m) / RATE
        if kind == 0:
            f = 2600 + 1400 * (t / dur)
        else:
            f = 3200 + 500 * np.sin(2 * np.pi * 28 * t)
        ph = np.cumsum(f) / RATE
        env = np.sin(np.pi * t / dur) ** 2
        chirp = np.sin(2 * np.pi * ph) * env * r.uniform(0.15, 0.35)
        place(out, stereo(chirp, r.uniform(-0.8, 0.8)), start)
    _save_world("amb_forest", out, 0.5)


def amb_ice():
    """冰原：空旷的风啸（带共鸣的窄带噪声，音高缓慢起伏）+ 偶尔冰面的细碎声，12 秒循环。"""
    n = 12 * RATE
    r = np.random.default_rng(42)
    noise = r.standard_normal((n, 2))
    t = np.arange(n) / RATE
    out = np.zeros((n, 2))
    for f0, amt in [(420, 0.5), (690, 0.35), (1150, 0.2)]:
        band = lowpass(highpass(noise, f0 * 0.85), f0 * 1.15, slope=4)
        swell = 0.6 + 0.4 * np.sin(2 * np.pi * t / 12.0 * r.integers(1, 3) + r.uniform(0, 6))
        out += band * swell[:, None] * amt
    out += lowpass(highpass(noise[:, ::-1], 150), 600) * 0.25
    _save_world("amb_ice", out, 0.5)


def amb_city():
    """城市：远处车流的低沉嗡鸣 + 偶尔很远的喇叭，12 秒循环。"""
    n = 12 * RATE
    r = np.random.default_rng(43)
    noise = r.standard_normal((n, 2))
    t = np.arange(n) / RATE
    out = lowpass(noise, 300) * (0.8 + 0.2 * np.sin(2 * np.pi * t / 6.0))[:, None]
    out += lowpass(highpass(noise[:, ::-1], 600), 2500) * 0.12
    for k in range(3):
        start = int(r.uniform(0, 12) * RATE)
        m = int(0.5 * RATE)
        tt = np.arange(m) / RATE
        f = r.choice([392.0, 440.0, 523.0])
        horn = (np.sign(np.sin(2 * np.pi * f * tt)) * 0.5 + np.sin(2 * np.pi * f * 1.26 * tt) * 0.5) * np.minimum(1, tt / 0.03) * np.exp(-tt * 2)
        place(out, stereo(lowpass(horn, 1500) * 0.08, r.uniform(-0.9, 0.9)), start)
    _save_world("amb_city", out, 0.5)


# ───────────────────────── S-14 风声 ─────────────────────────

def wind():
    """4 秒无缝循环：偏高频的白噪，带缓慢的阵风起伏。FFT 滤波本身是循环的，所以首尾自然接上。"""
    n = 4 * RATE
    noise = rng.standard_normal((n, 2))
    body = lowpass(highpass(noise, 500), 5000)
    hiss = highpass(noise[:, ::-1], 3000) * 0.35
    t = np.arange(n) / RATE
    gust = 0.8 + 0.2 * np.sin(2 * np.pi * t / 4.0) + 0.08 * np.sin(2 * np.pi * t * 3 / 4.0)
    out = (body + hiss) * gust[:, None]
    path = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "world")
    global OUT
    keep = OUT
    OUT = path
    save("wind", out, 0.7)
    OUT = keep


if __name__ == "__main__":
    import sys
    which = sys.argv[1:] or ["star_all", "ambient", "wind"]
    for name in which:
        if name in VARIANTS:
            star(name)
        else:
            globals()[name]()
