# 素材来源登记

游戏里用到的所有素材（模型、贴图、音乐、音效、字体、图片……）都在这里登记：从哪来、谁做的、什么许可、改过什么。
**以后每加一个素材、或者换掉一个素材，都要先在这里登记再提交。** 从网上拿的素材必须写清原始链接、作者和许可；用了 CC-BY 一类的素材，正式发布时要在游戏里署名。

来源分三类：
- **外部素材**：别人做的，从网上下载。
- **本项目合成**：Claude 用代码生成，没有用任何外部素材，版权归本项目。
- **引擎自带**：Godot 自带的东西。

## 总览

| 素材 | 位置 | 来源 | 许可 |
|---|---|---|---|
| 引擎声（4 个转速层） | `assets/audio/engine/on_*.ogg`、`off_*.ogg` | 外部：Freesound，EvanBoyerman | CC-BY 4.0，需署名 |
| 轮胎声（3 个状态） | `assets/audio/tires/*.ogg` | 外部：OpenGameArt，audible-edge (Tom Haigh) | CC-BY 3.0，需署名 |
| 音乐：星速（驾驶中，分底轨 / 鼓 / 主音三轨） | `assets/audio/music/star_base.ogg`、`star_drums.ogg`、`star_lead.ogg` | 本项目合成：`tools/make_music.py` | 本项目 |
| 音乐：氛围（标题、车库） | `assets/audio/music/ambient.ogg` | 本项目合成：`tools/make_music.py` | 本项目 |
| 风声 | `assets/audio/world/wind.ogg` | 本项目合成：`tools/make_music.py` | 本项目 |
| 撞车、爆炸、爆缸 | `assets/audio/world/crash.wav`、`explosion.wav`、`engine_blow.wav` | 本项目合成（2026-11-15 的一次性脚本，没有留在仓库里） | 本项目 |
| 断油声（已不用） | `assets/audio/engine/limiter.ogg` | 本项目合成（早期一次性脚本） | 本项目 |
| 界面音、字幕音、起动机、换挡、回火、掠过、贴纸、高光、白化、过弯评价铃声 | `assets/audio/sfx/*.wav` | 本项目合成：`tools/make_sfx.py` | 本项目 |
| 座舱、转速表、方向盘、贴纸 | `scripts/cockpit.gd`、`sticker_display.gd` | 本项目：引擎自带几何体拼的替身 | 本项目 |
| 路边景物、车库、基地、人物、远景环、云 | `scripts/scenery_models.gd`、`mesh_kit.gd`、`scenery.gd` | 本项目：代码生成的低多边形替身 | 本项目 |
| 流星、极光 | `scripts/gold_fx.gd` | 本项目：代码生成 | 本项目 |
| 画面风格（两级明暗、描边、16 色、抖动、像素化） | `shaders/*.gdshader` | 本项目 | 本项目 |
| 程序图标 | `icon.png`、`icon.ico` | 本项目：`tools/make_icon.py` 用代码画 | 本项目 |
| 字体 | 无字体文件 | 引擎自带：Godot 默认字体，中文由系统字体补字 | Godot 默认字体为 OFL；系统字体不随游戏分发 |

现在没有任何外部的模型、贴图、图片或字体。`game-spec/samples/` 里的风格样张和 Blender 试做模型只用于设计讨论，不进游戏。

## 外部素材详情

### 引擎声（assets/audio/engine/）

- 原始素材："Sports Car Accelerating/Speeding Up Fast - Exhaust"，作者 EvanBoyerman
  ——一台 3.2 升自然吸气 V6（VTEC）全力加速时，用领夹话筒在排气口上方录的声音。
- 来源：https://freesound.org/people/EvanBoyerman/sounds/754775/
- 许可：CC-BY 4.0（https://creativecommons.org/licenses/by/4.0/）
- 仓库里的源文件：`tools/audio_src/v6_vtec_exhaust_fast.mp3`（Freesound 的 MP3 预览版，未改动）。
- 用到的时间段：0.9–3.25 秒（一档）和 7.15–11.35 秒（二档），四层都取自这两段。
- 改动：转单声道；跟踪基频并把音高拉平到每层的基频（基频 = 转速 ÷ 40，即 50 / 87.5 / 137.5 / 200 Hz）；
  截取整数个周期，首尾交叉淡化成循环；四层响度拉齐；转成 OGG。`off_*.ogg` 是同样内容的副本。
- 重新生成：`python -I tools/make_engine_layers.py`
- 署名写法：Engine sound based on "Sports Car Accelerating/Speeding Up Fast - Exhaust" by EvanBoyerman (Freesound), CC BY 4.0, modified.

### 轮胎声（assets/audio/tires/）

`squeal_light.ogg`、`squeal_hard.ogg`、`struggle.ogg` 都由同一段录音加工而来：

- 原始素材："Car tire squeal skid loop"，作者 audible-edge (Tom Haigh)，由 qubodup 提交。
- 来源：https://opengameart.org/content/car-tire-squeal-skid-loop
- 许可：CC-BY 3.0（https://creativecommons.org/licenses/by/3.0/）
- 改动：重采样到 44.1 kHz 并转成 OGG。`squeal_light`（刚碰到极限）降调约 18%，加低通，减小音量；
  `squeal_hard`（处于极限中）升调约 12%，加 11 Hz 颤音；
  `struggle`（打滑）升调约 20%，加 17 Hz 颤音。
- 这三个是临时替身，之后可以换成同名的更合适的录音。
- 署名写法：Tire squeal based on "Car tire squeal skid loop" by audible-edge (Tom Haigh), OpenGameArt, CC BY 3.0, modified.

## 本项目合成的素材

- **音乐**：`tools/make_music.py`（numpy 合成 + ffmpeg 转 OGG）。
  - 星速：172 BPM 的鼓打贝斯，约 67 秒一循环；鼓、贝斯、和弦垫音、合成器主音都是代码算出来的波形。
  - 氛围：慢速的和弦垫音。
  - 两首都加了首尾相接的混响和延迟，循环时没有接缝。没有采样、没有外部音色库。
- **风声**：同一个脚本，滤波噪声。
- **音效**：`tools/make_sfx.py`（只用 Python 标准库）。
- 改了脚本后重新运行，再对 Godot 执行一次 `--headless --import`。
