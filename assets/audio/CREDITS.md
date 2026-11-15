# 音频来源与许可

## 轮胎声（assets/audio/tires/）

`squeal_light.ogg`、`squeal_hard.ogg`、`struggle.ogg` 都由同一段录音加工而来：

- 原始素材："Car tire squeal skid loop"，作者 audible-edge (Tom Haigh)，由 qubodup 提交
- 来源：https://opengameart.org/content/car-tire-squeal-skid-loop
- 许可：CC-BY 3.0（https://creativecommons.org/licenses/by/3.0/）
- 改动：重采样到 44.1 kHz 并转成 OGG；`squeal_light`（刚碰到极限）降调约 18% 并加低通、减小音量，
  `squeal_hard`（处于极限中）升调约 12% 并加 11 Hz 颤音，
  `struggle`（打滑）升调约 20% 并加 17 Hz 颤音（比"处于极限中"略高、略粗，两者故意做得接近）。

这三个文件是临时替身，之后可以用同名文件替换成更合适的录音。

## 引擎声（assets/audio/engine/）

`on_2000.ogg`、`on_3500.ogg`、`on_5500.ogg`、`on_8000.ogg`（`off_*.ogg` 是同样内容的副本）取自真实录音：

- 原始素材："Sports Car Accelerating/Speeding Up Fast - Exhaust"，作者 EvanBoyerman（Freesound）
  ——一台 3.2 升自然吸气 V6（VTEC）全力加速时，用领夹话筒在排气口上方录的声音
- 来源：https://freesound.org/people/EvanBoyerman/sounds/754775/
- 许可：CC-BY 4.0（https://creativecommons.org/licenses/by/4.0/）
- 仓库里的源文件：`tools/audio_src/v6_vtec_exhaust_fast.mp3`（Freesound 的 MP3 预览版，未改动）
- 用到的时间段：0.9–3.25 秒（一档）和 7.15–11.35 秒（二档）。四层都取自这两段。
- 改动：转单声道；跟踪基频并把音高拉平到每层该有的基频（基频 = 转速 ÷ 40，即 50 / 87.5 / 137.5 / 200 Hz）；
  截取整数个周期并把首尾交叉淡化成循环；四层响度拉齐；转成 OGG。
- 重新生成：`python -I tools/make_engine_layers.py`

`limiter.ogg` 是早先合成的断油声，现在不再使用（断油由引擎声自己的断续表现）。
