"""从 muted.io 的 Performance Cars 采样包（CC0）生成四个转速层的引擎循环声。

用法： python -I tools/make_engine_layers.py <解压后的采样包目录> <输出目录>

四层全部取自同一段录音（011 号开头 1.55 秒：同一辆车的一次轰油，基频从 70 Hz 连续升到 137 Hz），
所以各层音色一致。做法：
1. 跟踪这段录音的基频曲线；
2. 每一层取曲线上的一段，按瞬时基频做随时间变化的重采样，把音高"拉平"成这一层该有的基频
   （游戏里 基频 = 转速 ÷ 30，和早先合成音的音高一致）；
3. 截取整数个周期并把首尾交叉淡化成无缝循环，四层响度拉齐。
低转层取轰油的前半段，高转层取后半段，所以高转层带的是这台发动机高转时的音色。
"""
import subprocess, sys, os, wave
import numpy as np

SR = 48000
SOURCE = "011"
SRC_START, SRC_END = 0.0, 1.56
F0_START = 70.0                 # 这段开头的基频，跟踪的起点
RPM_TO_HZ = 1.0 / 30.0
# 层转速, 取基频曲线上的哪一段（Hz）
LAYERS = [
    (2000, 70.0, 100.0),
    (3500, 72.0, 126.0),
    (5500, 86.0, 137.0),
    (8000, 92.0, 137.0),
]
TARGET_RMS = 0.16
# 录音是远处收的，几乎只剩基频和二次谐波，听起来是闷的"嗡"，小音箱上低转几乎听不见。
# 所以对拉平后的波形做两步加工，把它本身的高次谐波提出来（不是另外叠加合成音）：
# 先按谐波次数提升高频（一阶微分混入），再做软削波。早先的合成音也是这种谐波丰富、带点失真的音色。
EMPHASIS = float(os.environ.get("ENGINE_EMPHASIS", "1.0"))
DRIVE = float(os.environ.get("ENGINE_DRIVE", "3.0"))
XFADE_PERIODS = 6


def load(path, a, b):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(a), "-t", str(b - a), "-i", path,
                          "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def f0_near(x, guess, span=0.12):
    """在 guess 附近 ±span 找自相关峰（抛物线插值），避免跳到倍频或半频。"""
    x = x - x.mean()
    n = len(x)
    spec = np.fft.rfft(x * np.hanning(n), 2 * n)
    ac = np.fft.irfft(np.abs(spec) ** 2)[:n]
    k0, k1 = int(SR / (guess * (1 + span))), int(SR / (guess * (1 - span))) + 1
    k = k0 + int(np.argmax(ac[k0:k1]))
    y0, y1, y2 = ac[k - 1], ac[k], ac[k + 1]
    d = y0 - 2 * y1 + y2
    if abs(d) > 1e-12:
        k += 0.5 * (y0 - y2) / d
    return SR / k


def track_f0(x):
    win, hop = int(0.08 * SR), int(0.01 * SR)
    times, freqs = [], []
    guess = F0_START
    for i in range(0, len(x) - win, hop):
        guess = f0_near(x[i:i + win], guess)
        times.append((i + win / 2) / SR)
        freqs.append(guess)
    coef = np.polyfit(times, freqs, 4)          # 平滑成一条曲线
    t = np.arange(len(x)) / SR
    curve = np.polyval(coef, np.clip(t, times[0], times[-1]))
    resid = np.sqrt(np.mean((np.polyval(coef, times) - np.array(freqs)) ** 2))
    return curve, resid


def flatten(x, curve, lo, hi, target):
    """取基频在 lo–hi 之间的那一段，重采样成恒定的 target Hz。"""
    idx = np.where((curve >= lo) & (curve <= hi))[0]
    a, b = idx[0], idx[-1]
    phase = np.cumsum(curve[a:b]) / SR              # 以"周期数"计的相位
    want = np.arange(0.0, phase[-1], target / SR)   # 输出每个采样点该处在的相位
    pos = np.interp(want, phase, np.arange(a, b))
    i = pos.astype(int)
    frac = pos - i
    return x[i] * (1 - frac) + x[np.minimum(i + 1, len(x) - 1)] * frac


def enrich(x, f0):
    d = np.gradient(x) * SR / (2 * np.pi * f0 * 3.0)     # 第 3 次谐波处增益为 1，次数越高提得越多
    y = x + EMPHASIS * d
    y /= np.sqrt((y ** 2).mean()) * 3.0                   # 归一到固定电平再削波，四层的失真程度相同
    return np.tanh(y * DRIVE)


def make_loop(x, period):
    fade = int(round(XFADE_PERIODS * period))
    body = int(round(int((len(x) - fade) / period) * period))
    t = np.linspace(0, np.pi / 2, fade)
    out = x[:body].copy()
    out[:fade] = x[:fade] * np.sin(t) + x[body:body + fade] * np.cos(t)
    return out


def brightness(x, f0):
    """各次谐波所在频带的能量占比（1–2 次、3–6 次、7 次以上），用来比较各层音色。"""
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    total = spec[f > f0 * 0.5].sum()
    return [spec[(f > f0 * a) & (f <= f0 * b)].sum() / total for a, b in ((0.5, 2.5), (2.5, 6.5), (6.5, 1e9))]


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    x = load(os.path.join(src, "%s-performance-cars-mutedio.wav" % SOURCE), SRC_START, SRC_END)
    curve, resid = track_f0(x)
    print("source f0 %.1f -> %.1f Hz, fit residual %.2f Hz" % (curve[0], curve[-1], resid))
    for rpm, lo, hi in LAYERS:
        target = rpm * RPM_TO_HZ
        y = flatten(x, curve, lo, hi, target)
        y = enrich(y, target)
        y = make_loop(y, SR / target)
        y -= y.mean()
        y *= TARGET_RMS / np.sqrt((y ** 2).mean())
        peak = np.abs(y).max()
        if peak > 0.98:
            y = np.tanh(y / peak * 1.5) / np.tanh(1.5) * 0.98
        check = f0_near(y, target, 0.1)
        wav = os.path.join(dst, "tmp_%d.wav" % rpm)
        with wave.open(wav, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())
        for prefix in ("on", "off"):
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-ar", "44100", "-c:a", "libvorbis",
                            "-q:a", "6", os.path.join(dst, "%s_%d.ogg" % (prefix, rpm))], check=True)
        os.remove(wav)
        mid = (lo + hi) / 2
        print("%d rpm: source %d-%d Hz -> %.1f Hz (shift x%.2f), measured %.1f Hz, loop %.2f s, peak %.2f, harmonics 1-2/3-6/7+ = %s"
              % (rpm, lo, hi, target, target / mid, check, len(y) / SR, peak,
                 " ".join("%.2f" % v for v in brightness(y, target))))


main()
