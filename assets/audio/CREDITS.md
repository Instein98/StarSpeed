# 音频来源与许可

## 轮胎声（assets/audio/tires/）

`squeal_light.ogg`、`squeal_hard.ogg`、`struggle.ogg` 都由同一段录音加工而来：

- 原始素材："Car tire squeal skid loop"，作者 audible-edge (Tom Haigh)，由 qubodup 提交
- 来源：https://opengameart.org/content/car-tire-squeal-skid-loop
- 许可：CC-BY 3.0（https://creativecommons.org/licenses/by/3.0/）
- 改动：重采样到 44.1 kHz 并转成 OGG；`squeal_light`（刚碰到极限）降调约 18% 并加低通、减小音量，
  `squeal_hard`（处于极限中）升调约 12% 并加 11 Hz 颤音，
  `struggle`（打滑）升高约 7 个半音并加削波失真和 31 Hz 颤音。

这三个文件是临时替身，之后可以用同名文件替换成更合适的录音。

## 引擎声（assets/audio/engine/）

`on_2000.ogg`、`on_3500.ogg`、`on_5500.ogg`、`on_8000.ogg`（`off_*.ogg` 是同样内容的副本）取自真实录音：

- 原始素材："Performance Cars" 免费采样包，muted.io
- 来源：https://muted.io/performance-cars
- 许可：CC0
- 用到的文件和时间段：011 号开头 1.56 秒（同一辆车的一次轰油，基频从 70 Hz 升到约 132 Hz）。四层都取自这一段。
- 改动：转单声道；跟踪基频并把音高拉平到每层该有的基频（基频 = 转速 ÷ 30，即 66.7 / 116.7 / 183.3 / 266.7 Hz）；
  提升高次谐波并做软削波（原录音偏闷）；截取整数个周期并把首尾交叉淡化成循环；四层响度拉齐；转成 OGG。
- 重新生成：`python -I tools/make_engine_layers.py <解压后的采样包目录> assets/audio/engine`

`limiter.ogg` 是早先合成的断油声，现在不再使用（断油由引擎声自己的断续表现）。
