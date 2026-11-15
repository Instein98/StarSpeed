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

`on_*.ogg`、`off_*.ogg`、`limiter.ogg` 目前是用脚本合成的临时占位音（非录音，无第三方版权），
等开发者放入真实录音后同名覆盖。
