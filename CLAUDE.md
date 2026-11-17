# Star Speed（星速）— Godot 4.5.1 第一人称赛车 demo

车在轨道上跑（不能左右转向），玩家只控制油门、刹车、升降档。玩法核心是进弯前把车速降到弯道极限以下，以及在长直道和高速弯上体验极速。

**先读 `STATUS.md`**：它记录了现在做到哪、和规格的差别、接下来要做什么。每完成一块就更新它。

和开发者用中文交流。开发者通过试玩给反馈，每一轮反馈改完都要提交一次 commit。

## 运行与检查

- Godot：`D:\Software\Godot_v4.5.1\Godot_v4.5.1-stable_win64.exe`（带控制台输出的是 `..._console.exe`）。
- 开发者自己试玩：直接用 Godot 打开项目运行，默认全屏。
- **Claude 自己运行 Godot 时，不能在开发者屏幕上弹出窗口，也不能出声。**
  - 只查逻辑：`--headless`。
  - 需要真实渲染（截图、帧率）：用 `tools/hidden_run.ps1` 在隐藏的 Windows 桌面上启动，并且必须加 `--audio-driver Dummy`。项目设成了全屏，`--windowed` 不起作用。
- 规则检查（每次改完规则、赛道、调参都要跑，应全部通过）：

```bash
"D:/Software/Godot_v4.5.1/Godot_v4.5.1-stable_win64_console.exe" --headless --path . --script tools/rule_checks.gd
```

  输出最后一行是"结果：N 通过，M 失败"。退出后打印的 `grade_at ... Nil` 错误是退出时的残留，可以忽略。输出重定向到文件再读，不要接管道到 `tail`。
- 隐藏桌面运行的写法（PowerShell，必须在同一进程里用 `&` 调用）：

```powershell
$cmd = '"D:\Software\Godot_v4.5.1\Godot_v4.5.1-stable_win64.exe" --path "D:\Claude\egm-game-prototypes\star-speed" --audio-driver Dummy --log-file "<日志路径>" --script "<脚本路径>"'
& "tools\hidden_run.ps1" -CommandLine $cmd -TimeoutSec 120
```

  截图脚本是一个 `extends SceneTree` 的脚本：实例化 `res://scenes/main.tscn`，把 `CarSim.use_device_input` 设为 false，用 `car.place(path, s, v, gear, from_access)` 摆车，`await RenderingServer.frame_post_draw` 后 `root.get_texture().get_image().save_png(...)`。
- 声音好不好、动态手感，Claude 验证不了，要如实告诉开发者需要他来试。

## 按键

W 或空格 = 油门，S = 刹车，↑ / ↓ = 升 / 降档（菜单里是上下选择），回车 = 确定 / 回大本营，Esc = 暂停菜单。
调试：F2 重新读取调参文件，F3 调试面板，F4 跳到下一个区段起点，F5 轮换画面方案。

## 一局的流程（`scripts/run_flow.gd`）

- 大本营：车停在车库里，选"主赛道 计时赛"或"练习环道"，回车出发。两者共用出库路，在岔路口分开（计时赛直行，练习拐进环道）。
- 计时赛：过森林起点线开始计时，三个区段连着跑；撞车、爆缸都是爆炸后退到弯前复位，计时不停。过城市终点线显示结算（各区段用时、总用时、是否新纪录），车自己刹停，回车回大本营。
- 练习：在环道上随便绕圈，不计时，回车回大本营。
- 最好成绩存在 `user://save.json`（`SaveData.data` 的 `best_total`、`best_sections`）。**Claude 的测试脚本如果会跑到结算，结束前要把这两项还原再 `save()`，不要把假成绩留在开发者的存档里。最稳妥的做法是开头 `var keep = SaveData.data.duplicate(true)`，结尾 `SaveData.data = keep; SaveData.save()`（包括 `best_medals`）。**
- F4 调试瞬移会直接进入计时赛状态；没跑过的区段没有成绩，不记总成绩。

## 结构

- `game-spec/game_spec.md`：最初的规格。**不要修改 `game-spec/` 里的任何文件。** 规格只做了第 12 节 Build Order 的阶段 1–4；之后的改动都来自开发者试玩反馈，很多地方已经和规格不一致（见下）。两者冲突时以开发者的反馈为准。
- `data/tuning.tres`（类型 `scripts/tuning_data.gd`）：所有数值。**数值不要写死在脚本里**，加新数值就在这两个文件里加字段。脚本里用 `Tuning.d.<字段>` 读。`tNN_` 开头的对应规格的调参表 T-NN，其余是试玩后加的。
- `data/engine_mix_default.json`：声音混合参数。
- `data/track_access.tres`、`track_loop.tres`、`track_main.tres`：赛道分段表（直道 / 左弯 / 右弯、半径、角度、长度、坡度）。主赛道分森林、冰原、城市三个区段。
- `scripts/car_sim.gd`：全部驾驶规则，不碰画面和声音。`scripts/track.gd`：由分段表生成路面和查询接口。`scripts/main.gd`：把各节点连起来，外加临时的失败演出、复位、测试方块。
- `scripts/camera_rig.gd`（视野、震动、转向不足时的歪头）、`speed_fx.gd` + `shaders/post_world.gdshader`（景物拉线）、`cockpit.gd`（临时座舱和转速表）、`minimap.gd`、`engine_audio.gd`、`tire_audio.gd`、`explosion.gd`。
- `tools/`：规则检查脚本和隐藏桌面启动器（带 `.gdignore`，不属于游戏）。
- 没有 Blender 模型：座舱、仪表、路边景物全是引擎自带几何体的临时替身。路两侧的彩色方块是临时参照物。

## 当前行为里和规格不一样的地方

- 有刹车（规格没有）。8 个档，极速是 8 档 8500 转 = 680 km/h（`top_speed_kmh`），到了就不再加速。
- 打滑是物理算的：车速超过弯道极限车速就向弯外侧滑，降回极限以下就拉回原路线，滑到离中心线 `slide_wall_m` 才算撞。没有规格里的挣扎计时器。
- 失败后是"爆炸 → 退到弯前复位"，不是 Game Over 和进场回放。失败原因靠演出表现，不显示文字。
- 轮胎相关的画面抖动全部去掉；接近极限和打滑时视角向弯内侧偏转、歪头。
- 景物速度感用按深度的运动拉线（画面方案 M），不是规格的"清晰圆 + 线化"。
- 速度效果（震动、视野、拉线）随车速按幂曲线增长，中低速很弱，极速很夸张；换挡瞬间没有视野跳变。
- 引擎声的音调和响度只跟转速走，与油门、档位、换挡无关；转速在声音里是连续扫过去的；断油是引擎声自己的断续。
- 轮胎声三个状态：刚碰到极限、处于极限中、打滑。
- 救回原路线时，横向速度不超过 车速 × tan(`slide_return_max_angle_deg`)，画面上车头朝原路线偏（不是横着平移）；车停住就回不了线。
- 小地图保持规格的样子。试过斜 45° 带网格的放大版，开发者不喜欢，已改回。
- 主赛道的设计原则（开发者 2026-11-15）：每个区段只有一处能到极速，一次最多持续 2–3 秒；能到 7 档高转（约 507 km/h 以上）的地方每个区段最多 3 处；区段交界的长直道可以快但不到极速。改赛道后用 `tools/track_design.gd` 量这几个数（headless 运行，会用刹车的模拟驾驶员）。
- 区段起终点在地面上有黑白棋盘格线（`Track.gate_s`；森林的起点线在主赛道 150 m 处）。右上角显示最近 3 个区段的成绩；凡是刷新历史最好的时间，游戏里所有地方都用紫色显示（名字保持正常颜色）。
- 爆缸没有单独的音效，直接爆炸。
- 三个区段各有一套环境（`data/env_forest/ice/city.tres`），主赛道上过区段起点线时 2 秒过渡（`main.gd` 的 `_update_environment`）。
- 奖牌贴纸：过区段终点线按 T-53 评定，高于存档等级就存档并在挡风玻璃右侧弹出（`sticker_display.gd`，存档键 `best_medals`）。贴纸盘面用自发光，否则背光面会把金色压成铜色。

## 已知的坑

- GDScript 里把字典里的 PackedArray 用 `as` 转型后 `append`，改的是副本。要原地追加就用普通 `Array`。
- 岔路口、并入口附近不放测试方块（`main.gd` 的 `_near_road`），急弯自己的两侧要有。改这块后从正上方截图核对。
- 引擎声的四个转速层由 `tools/make_engine_layers.py` 从同一段真实录音生成（`tools/audio_src/` 里的自吸 V6 排气口录音，CC-BY 4.0），四层同源所以音色一致。开发者要的是"公认好听、让人兴奋的自吸跑车排气声"，并且各层必须一致；试过每层用不同车的录音（6000 转前后明显不连贯）和 muted.io 采样包里的录音（不够兴奋），都被否决了。音频来源和许可写在 `assets/audio/CREDITS.md`，用了别人的素材要在那里登记。
- 新加了带 `class_name` 的脚本后，也要先跑一次 `--headless --import`，否则命令行运行会报找不到这个类型并卡住。
- 替换音频文件后，Claude 自己跑 Godot 前要先执行一次 `--headless --import`，否则读到的还是旧的导入缓存。

## 提交

每完成一项改动或一轮反馈就提交一次，提交信息用英文、说明改了什么和为什么。**每次提交后都推送**到 `origin`（git@github.com:Instein98/StarSpeed.git，分支 `main`）。
