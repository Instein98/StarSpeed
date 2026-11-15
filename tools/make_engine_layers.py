"""从 muted.io 的 Performance Cars 采样包（CC0）切出四个转速层的引擎循环声。

用法： python -I tools/make_engine_layers.py <解压后的采样包目录> <输出目录>

做法：每一层取一段转速稳定的真实录音，量出它的基频，重采样到这一层该有的基频
（游戏里 基频 = 转速 ÷ 25），截取整数个周期并把首尾交叉淡化成无缝循环，再把四层的响度拉齐。
"""
import subprocess, sys, os, wave
import numpy as np

SR = 48000
RPM_TO_HZ = 1.0 / 25.0
# 层转速, 文件编号, 起点秒, 终点秒, 基频搜索范围
LAYERS = [
    (2000, "003", 1.0, 6.5, (50, 80)),      # 低转稳定段，基频约 62 Hz
    (3500, "034", 27.4, 29.2, (140, 190)),  # 中转稳定段，基频约 163 Hz
    (5500, "034", 27.4, 29.2, (140, 190)),  # 同一段升调（没有更合适的中高转稳定段）
    (8000, "029", 6.0, 16.0, (280, 360)),   # 高转长时间稳定段，基频约 320 Hz
]
TARGET_RMS = 0.16
XFADE = 0.12


def load(path, a, b):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(a), "-t", str(b - a), "-i", path,
                          "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def f0(x, lo, hi):
    """长窗自相关 + 抛物线插值，取整段的平均基频。"""
    x = x - x.mean()
    n = len(x)
    spec = np.fft.rfft(x * np.hanning(n), 2 * n)
    ac = np.fft.irfft(np.abs(spec) ** 2)[:n]
    k0, k1 = int(SR / hi), int(SR / lo)
    k = k0 + int(np.argmax(ac[k0:k1]))
    y0, y1, y2 = ac[k - 1], ac[k], ac[k + 1]
    k += 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2)
    return SR / k


def resample(x, ratio):
    """ratio > 1 升调（变短）。线性插值足够：之后还会被引擎按转速连续变调。"""
    idx = np.arange(0, len(x) - 1, ratio)
    i = idx.astype(int)
    frac = idx - i
    return x[i] * (1 - frac) + x[i + 1] * frac


def make_loop(x, period):
    fade = int(round(XFADE * SR / period)) * period          # 交叉长度取整数个周期
    fade = int(round(fade))
    body = int((len(x) - fade) / period) * period            # 循环长度取整数个周期
    body = int(round(body))
    t = np.linspace(0, np.pi / 2, fade)
    out = x[:body].copy()
    out[:fade] = x[:fade] * np.sin(t) + x[body:body + fade] * np.cos(t)
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    for rpm, num, a, b, (lo, hi) in LAYERS:
        x = load(os.path.join(src, "%s-performance-cars-mutedio.wav" % num), a, b)
        measured = f0(x, lo, hi)
        target = rpm * RPM_TO_HZ
        y = resample(x, target / measured)
        y = make_loop(y, SR / target)
        y -= y.mean()
        y *= TARGET_RMS / np.sqrt((y ** 2).mean())
        peak = np.abs(y).max()
        if peak > 0.98:
            y = np.tanh(y / peak * 1.5) / np.tanh(1.5) * 0.98   # 极少数尖峰软削
        check = f0(y, target * 0.85, target * 1.15)
        wav = os.path.join(dst, "tmp_%d.wav" % rpm)
        with wave.open(wav, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())
        for prefix in ("on", "off"):
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-ar", "44100", "-c:a", "libvorbis",
                            "-q:a", "6", os.path.join(dst, "%s_%d.ogg" % (prefix, rpm))], check=True)
        os.remove(wav)
        print("%d rpm: 源 %s %.1f–%.1f s 基频 %.1f Hz → 目标 %.1f Hz（变调 ×%.2f），成品 %.1f Hz，循环 %.2f 秒，峰值 %.2f"
              % (rpm, num, a, b, measured, target, target / measured, check, len(y) / SR, peak))


main()
