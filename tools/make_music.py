"""用代码合成两首临时音乐（规格 10.2）。开发者同意下载正式素材之前用它们顶上。

    python tools/make_music.py

需要 numpy 和 ffmpeg（输出 OGG Vorbis）。所有延迟和混响都按"循环"计算（首尾相接），所以导出的文件无缝循环。
  assets/audio/music/star.ogg     M-01 星速：172 BPM 的鼓打贝斯，明亮的合成器主音，无人声，从第一拍就是高潮，约 67 秒
  assets/audio/music/ambient.ogg  M-02 氛围：安静的合成器长音铺底，无节拍，空旷的回响，96 秒
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


def star():
    bpm = 172.0
    beat = 60.0 / bpm
    bars = 48
    n = int(round(bars * 4 * beat * RATE))
    six = beat / 4.0
    mix = np.zeros((n, 2))
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
                place(mix, stereo(hat * v, -0.3), int((b0 + k * six) * RATE))
            elif rng.random() < 0.35:
                place(mix, stereo(hat * 0.18, 0.3), int((b0 + k * six) * RATE))
        place(mix, stereo(ohat * 0.35, 0.4), int((b0 + 6 * six) * RATE))

    # 和弦进行（A 小调，每两小节换一个）：Am F C G
    prog = [(57, [0, 3, 7]), (53, [0, 4, 7]), (60, [0, 4, 7]), (55, [0, 4, 7])]
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
        tones = [root + 12 + iv for iv in chord] + [root + 24]
        steps = 32
        for k in range(steps):
            if pattern_kind == 0:
                note = tones[k % 4]
            elif pattern_kind == 1:
                note = tones[[0, 2, 1, 3, 2, 1, 3, 2][k % 8]] + (12 if k % 16 >= 12 else 0)
            else:
                note = tones[[3, 2, 1, 0][k % 4]] + (12 if (k // 4) % 2 else 0)
            st = s + int(k * six * RATE)
            ln = int(six * 0.9 * RATE)
            f = midi(note)
            tone = 0.6 * osc(f, ln, "square") + 0.4 * osc(f * 1.005, ln, "saw")
            seg = tone * adsr(ln, 0.003, 0.06, 0.45, 0.02)
            place(lead, seg, st)
    bass = lowpass(bass, 380) * side
    pad = lowpass(pad, 2200) * side
    lead = lowpass(lead, 5200)
    mix += stereo(bass * 0.55)
    mix += stereo(pad * 0.10, -0.4) * 0.5 + stereo(pad * 0.10, 0.4) * 0.5
    lead_st = delay(stereo(lead * 0.22), beat * 0.75, 0.45, 0.5)
    mix += reverb(lead_st, 1.2, 0.18, seed=3)
    save("star", np.tanh(mix * 1.3))


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


if __name__ == "__main__":
    star()
    ambient()
