class_name RunFlow
extends Control
## 一局的流程和它的界面（开发者 2026-11-15 定的）：
##   大本营：车停在车库里，选"主赛道 计时赛"或"练习环道"，回车出发。
##   计时赛：出库后在岔路口直行上主赛道，过森林起点线开始计时，三个区段连着跑；
##           撞车、爆缸都是爆炸后退到弯前复位，计时不停。过城市终点线后显示结算，回车回大本营。
##   练习：出库后在岔路口拐进环道随便绕圈，不计时；回车回大本营。
##   暂停：Esc。继续 / 回大本营 / 回到标题 / 退出游戏。
## 标题画面和点火（规格 6.1、6.8、9.2、9.3）：启动后先是标题画面（漆黑座舱、贴纸被小灯照亮），
## 选"开始"进点火提示，长按油门 T-50 秒点火：指针从 0 扫到 9000，点着后窗外揭开（V-01），然后到大本营。
## 这个节点在暂停时也照常运行（process_mode = ALWAYS），界面用 _draw 画在 960×540 的网格上。

enum State { TITLE, IGNITE, IGNITING, BASE, PRACTICE, RUN, RESULTS, ENDING, INVITE, INTRO }

const GRID := Vector2(960.0, 540.0)
const COL_TEXT := Color("f7ecd4")
const COL_GOLD := Color("ffc93c")
const COL_DIM := Color("8a93a3")
## 历史最好成绩的时间一律用紫色显示（右上角、结算），名字保持正常颜色
const COL_RECORD := Color("c77dff")
const RECENT_COUNT := 3
const COL_SHADE := Color(0.06, 0.08, 0.13, 0.72)
## 和最好成绩比的差值：快了绿色、慢了朱红
const COL_FASTER := Color("7bd65a")
const COL_SLOWER := Color("ef4a2f")
const BASE_OPTIONS: Array[String] = ["主赛道  计时赛", "单区段  森林", "单区段  冰原", "单区段  城市", "练习环道"]
const BASE_PRACTICE := 4
const PAUSE_OPTIONS: Array[String] = ["继续", "重新开始", "设置", "键位设置", "回大本营", "回到标题", "退出游戏"]
const PAUSE_RESTART := 1   ## "重新开始"只在计时赛里出现
## 设置界面（开发者 2026-11-19 第 1 轮 #4）的行
const SET_ROWS: Array[String] = ["vol_master", "vol_music", "vol_sfx", "fullscreen", "ghost_on", "auto_shift", "speedo", "fx_level", "lang", "clear"]
const SET_ROW_NAMES: Array[String] = ["总音量", "音乐", "音效", "全屏", "幽灵（最好成绩）", "换挡", "车速数字", "画面效果", "语言", "清除成绩"]
const FX_LEVEL_NAMES: Array[String] = ["完整", "减弱", "最弱"]
## 键位设置（9.10）的行：四个可改键的动作、降档提示灯辅助开关、恢复默认
const KEY_ROWS: Array[String] = ["throttle", "brake", "shift_up", "shift_down", "assist", "reset"]
const KEY_ROW_NAMES: Array[String] = ["油门", "刹车", "升档", "降档", "辅助：降档提示灯", "恢复默认"]
# 9.1 界面颜色
const COL_DARK := Color("1b2233")
const COL_DARKER := Color("0f1424")
const COL_RED := Color("ef4a2f")
const COL_ROAD := Color("4a5262")
const BUTTON_SIZE := Vector2(320.0, 44.0)
# 点火演出（规格 4.3 的"点火演出"、8.3、8.5 V-01）
const IGNITE_TIME := 1.2
const REVEAL_START := 0.6
const REVEAL_TIME := 0.35
const LIGHT_UP_FROM := 0.6
const LIGHT_UP_TO := 0.95
const COCKPIT_DARK := 0.15
const TACH_DARK := 0.3
const START_BLIP_RPM := 4200.0
const START_BLIP_TIME := 0.22

var state := State.TITLE
var paused := false
var section_times: Array[float] = [-1.0, -1.0, -1.0]   ## 本局各区段用时，−1 = 没有
var new_record := false
var section_records: Array[bool] = [false, false, false]   ## 本局各区段是否刷新了历史最好
var section_medals: Array[int] = [0, 0, 0]                  ## 本局各区段评到的贴纸等级
## 本局统计（开发者 2026-11-19 第 2 轮 #2）：撞车 / 爆缸次数、最高车速（km/h）。完美过弯数在 CornerJudge.counts
var run_crashes := 0
## 单区段计时赛（开发者 2026-11-19 第 2 轮 #3）：只跑这一个区段，跑完显示结算；−1 = 三段连跑
var single_section := -1
## 大本营下方信息的页（← → 切换）：0 奖牌、1 本地排行、2 累计统计
var _base_page := 0
const BASE_PAGES := 4
const TOP_RUNS := 5
## 本局在本地排行里的名次（1 起），没进前 5 为 0
var run_rank := 0
## 练习环道的圈速（第 3 轮 #5）：第一次经过环道起点开始计，之后每圈一次；最快圈存档 best_lap
var _lap_t := -1.0
var _last_lap := -1.0
var _prev_loop_s := -1.0
var _lap_record := false
var run_top_kmh := 0.0
var _cockpit: Cockpit
## 右上角显示的最近 3 个区段成绩：{name, time, record}，新的在下面；跨局保留
var recent: Array[Dictionary] = []

var _main: Node
var _car: CarSim
var _track: Track
var _hint: Label
var _select := 0
var _pause_select := 0
var _font: Font
var _title_select := 0
var _ignite_hold := 0.0
var _ignite_time := 0.0
var _need_release := false
var _blink := 0.0
## 本局各区段出发时的历史最高贴纸等级（结尾面板的"新纪录"标记用）
var _start_medals: Array = [0, 0, 0]
var _end_t := 0.0
var _end_steps_done := 0
## 字幕条（9.3）：说话人、文字、剩余秒数（< 0 = 一直显示到被替换）、是否要按键推进
var caption_speaker := ""
var caption_text := ""
var caption_left := 0.0
var caption_wait_key := false
# 结尾（6.7）
const END_WHITE := 1.0
const END_TURN := 1.5
const END_SWEEP_GAP := 0.5
const END_CAPTION := "欢迎回来。这台车，只有你开得了。"
const END_CAPTION_TIME := 5.0
# 开场字幕（9.3）。第 3、4 条按现在有刹车改过（规格原文是"它没有刹车"，见 QUESTIONS.md）
const INTRO_LINES: Array[String] = [
	"欢迎。你现在坐在星速跑车里。",
	"它的加速能力来自外星科技。我们自己的试车手，没有一个敢把它开到头。",
	"这辆车是为速度而生。刹车只够你在弯前活下来，别指望它替你开车。",
	"想慢下来：按 %s 刹车，或者松开油门、按 %s 降档，让引擎把车拖住。",
	"启动设备已经接好。准备好了，就长按 %s 点火。",
]
var _intro_line := 0
var _keys_open := false
var _keys_sel := 0
var _keys_listen := false
## 9.6 的贴纸文字面板：越线后 0.3–2.5 秒显示
var _medal_panel_t := -1.0
var _medal_panel: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = GRID
	_font = ThemeDB.fallback_font


func setup(p_main: Node, p_car: CarSim, p_track: Track, p_hint: Label, p_cockpit: Cockpit) -> void:
	_cockpit = p_cockpit
	sync_medals()
	Achievements.backfill()
	var medals: Array = SaveData.data.get("best_medals", [0, 0, 0])
	for i in 3:
		_cockpit.stickers.set_tier(i, int(medals[i]))
	_main = p_main
	_car = p_car
	_track = p_track
	_hint = p_hint
	_car.failed.connect(func(_k: int) -> void:
		if state in [State.RUN, State.PRACTICE]:
			SaveData.stat_add("crashes", 1)
		if state == State.RUN:
			run_crashes += 1)


# ───────────────────────── 键位设置（9.10） ─────────────────────────

func open_keys() -> void:
	_keys_open = true
	_keys_sel = 0
	_keys_listen = false


func _keys_input(event: InputEvent) -> void:
	if _keys_listen:
		if event is InputEventKey and event.pressed and not event.echo:
			var code := (event as InputEventKey).physical_keycode
			if code == KEY_ESCAPE:
				_keys_listen = false
				_main.sfx.play("ui_back")
			elif SaveData.set_key(KEY_ROWS[_keys_sel], code):
				_keys_listen = false
				_main.sfx.play("ui_ok")
			else:
				_main.sfx.play("ui_back")       # 不允许的键：继续等
		return
	if event.is_action_pressed("pause"):
		_keys_open = false
		_main.sfx.play("ui_back")
	elif event.is_action_pressed("ui_up"):
		_keys_sel = posmod(_keys_sel - 1, KEY_ROWS.size())
		_main.sfx.play("ui_move")
	elif event.is_action_pressed("ui_down"):
		_keys_sel = posmod(_keys_sel + 1, KEY_ROWS.size())
		_main.sfx.play("ui_move")
	elif event.is_action_pressed("confirm"):
		_main.sfx.play("ui_ok")
		match KEY_ROWS[_keys_sel]:
			"assist":
				SaveData.data["assist_downshift_lamp"] = not bool(SaveData.data.get("assist_downshift_lamp", false))
				SaveData.save()
			"reset":
				SaveData.reset_keys()
			_:
				_keys_listen = true


func _draw_keys() -> void:
	draw_rect(Rect2(Vector2.ZERO, GRID), COL_SHADE)
	var r := Rect2(Vector2(220.0, 70.0), Vector2(520.0, 440.0))
	_draw_panel(r)
	_text_center(Loc.t("键位设置"), 86.0 + 36.0, 36, COL_GOLD)
	for i in KEY_ROWS.size():
		var y := 150.0 + 52.0 * i
		var row := KEY_ROWS[i]
		var sel := i == _keys_sel
		if row == "reset":
			_draw_button(Loc.t(KEY_ROW_NAMES[i]), Vector2(480.0, y), sel, true)
			continue
		draw_string(_font, Vector2(250.0, y + 30.0), Loc.t(KEY_ROW_NAMES[i]), HORIZONTAL_ALIGNMENT_LEFT, 250.0, 24 if row != "assist" else 18, COL_TEXT)
		var label := ""
		if row == "assist":
			label = Loc.t("开") if bool(SaveData.data.get("assist_downshift_lamp", false)) else Loc.t("关")
		elif sel and _keys_listen:
			label = Loc.t("按下新键…") if _blink < 0.5 else ""
		else:
			label = SaveData.key_label(row)
		var box := Rect2(Vector2(610.0 - 80.0, y), Vector2(160.0, 44.0))
		var fill := COL_GOLD if sel else COL_DARK
		draw_rect(box, COL_TEXT)
		draw_rect(box.grow(-4.0), fill)
		draw_string(_font, Vector2(box.position.x, y + 30.0), label, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 20, COL_DARK if sel else COL_TEXT)
		if sel:
			var tip := Vector2(232.0, y + 22.0)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(8.0, 0.0), tip + Vector2(-6.0, -8.0), tip + Vector2(-6.0, 8.0)]), COL_RED)
	draw_string(_font, Vector2(0.0, 474.0 + 11.0), Loc.t("手柄：RT 油门  LT 刹车  RB / Y 升档  LB / X 降档  A 确定  Start 暂停  Back 重开"), HORIZONTAL_ALIGNMENT_CENTER, GRID.x, 11, COL_DIM)
	draw_string(_font, Vector2(0.0, 486.0 + 12.0), Loc.t("回车 改键   Esc 返回"), HORIZONTAL_ALIGNMENT_CENTER, GRID.x, 12, COL_DIM)


# ───────────────────────── 制作人员（开发者 2026-11-19 第 1 轮 #5） ─────────────────────────
## CC-BY 素材的许可要求在游戏里署名；内容和 ASSET_SOURCES.md 保持一致。[标题, 内容…]

const CREDITS: Array = [
	["制作", "Star Speed 开发组"],
	["引擎", "Godot Engine 4.5 — MIT License", "© Juan Linietsky, Ariel Manzur and contributors"],
	["引擎声", "\"Sports Car Accelerating/Speeding Up Fast - Exhaust\" by EvanBoyerman (Freesound)", "CC BY 4.0 — modified"],
	["轮胎声", "\"Car tire squeal skid loop\" by audible-edge (Tom Haigh), OpenGameArt", "CC BY 3.0 — modified"],
	["音乐、其余音效、模型", "本项目用代码生成"],
]
var _credits_open := false
var _help_open := false


## 怎么玩（开发者 2026-11-19 第 2 轮 #5）：规则和按键一页说清，按键随改键显示。
func _draw_help() -> void:
	draw_rect(Rect2(Vector2.ZERO, GRID), COL_SHADE)
	_draw_panel(Rect2(Vector2(90.0, 50.0), Vector2(780.0, 460.0)))
	_text_center(Loc.t("怎么玩"), 66.0 + 36.0, 36, COL_GOLD)
	var k := func(a: String) -> String: return "[" + SaveData.key_label(a) + "]"
	var lines := [
		[Loc.t("目标"), Loc.t("森林、冰原、城市三个区段连着跑，比总用时；也可以单独跑一段。")],
		[Loc.t("操作"), Loc.t("油门 %s   刹车 %s   升档 %s   降档 %s   重开 [R]   暂停 [Esc]") % [k.call("throttle"), k.call("brake"), k.call("shift_up"), k.call("shift_down")]],
		[Loc.t("换挡"), Loc.t("指针进红区前升档。顶着断油太久，引擎会爆。")],
		[Loc.t("降档"), Loc.t("降档后转速冲过表盘尽头会爆缸：等指针落下来再降。")],
		[Loc.t("过弯"), Loc.t("进弯前把车速降到弯道极限以下。轮胎越叫越尖 = 越接近极限。")],
		[Loc.t("打滑"), Loc.t("太快会往弯外滑：松油门、刹车或降档把车救回来；滑到护栏就撞车。")],
		[Loc.t("奖励"), Loc.t("贴着极限过弯有\"完美过弯\"；跑得越接近理想车速，音乐越完整。")],
		[Loc.t("对手"), Loc.t("青色的半透明车是你最好那趟的幽灵；右上角是和最好成绩的差值。")],
	]
	var y := 150.0
	for row: Array in lines:
		draw_string(_font, Vector2(120.0, y + 16.0), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, COL_GOLD)
		draw_string(_font, Vector2(190.0, y + 16.0), str(row[1]), HORIZONTAL_ALIGNMENT_LEFT, 650.0, 15, COL_TEXT)
		y += 38.0
	_text_center(Loc.t("回车 / Esc 返回"), 492.0, 12, COL_DIM)


func _draw_credits() -> void:
	draw_rect(Rect2(Vector2.ZERO, GRID), COL_SHADE)
	_draw_panel(Rect2(Vector2(120.0, 60.0), Vector2(720.0, 440.0)))
	_text_center(Loc.t("制作人员"), 76.0 + 36.0, 36, COL_GOLD)
	var y := 160.0
	for block: Array in CREDITS:
		_text_center(Loc.t(str(block[0])), y, 14, COL_DIM)
		y += 22.0
		for i in range(1, block.size()):
			_text_center(Loc.t(str(block[i])), y, 16 if i == 1 else 12, COL_TEXT if i == 1 else COL_DIM)
			y += 20.0 if i == 1 else 18.0
		y += 12.0
	_text_center(Loc.t("回车 / Esc 返回"), 482.0, 12, COL_DIM)


# ───────────────────────── 设置（开发者 2026-11-19 第 1 轮 #4） ─────────────────────────

var _set_open := false
var _set_sel := 0
var _clear_armed := false


func open_settings() -> void:
	_set_open = true
	_set_sel = 0
	_clear_armed = false


func _settings_input(event: InputEvent) -> void:
	var row := SET_ROWS[_set_sel]
	if event.is_action_pressed("pause"):
		_set_open = false
		_main.sfx.play("ui_back")
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		_set_sel = posmod(_set_sel + (-1 if event.is_action_pressed("ui_up") else 1), SET_ROWS.size())
		_clear_armed = false
		_main.sfx.play("ui_move")
	elif row.begins_with("vol_") and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
		var step := -1 if event.is_action_pressed("ui_left") else 1
		SaveData.data[row] = clampi(int(SaveData.data.get(row, 8)) + step, 0, 10)
		SaveData.apply_settings()
		SaveData.save()
		_main.sfx.play("ui_move")
	elif event.is_action_pressed("confirm") or (not row.begins_with("vol_") and row != "clear" \
			and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"))):
		match row:
			"lang":
				Loc.toggle()
				_main.sfx.play("ui_ok")
			"fx_level":
				var step := -1 if event.is_action_pressed("ui_left") else 1
				SaveData.data["fx_level"] = posmod(int(SaveData.data.get("fx_level", 0)) + step, FX_LEVEL_NAMES.size())
				SaveData.save()
				_main.sfx.play("ui_ok")
			"fullscreen", "ghost_on", "auto_shift", "speedo":
				SaveData.data[row] = not bool(SaveData.data.get(row, _default_on(row)))
				SaveData.apply_settings()
				SaveData.save()
				_main.sfx.play("ui_ok")
			"clear":
				if not _clear_armed:
					_clear_armed = true
					_main.sfx.play("ui_move")
				else:
					_clear_armed = false
					SaveData.clear_records()
					_main.ghost.best = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
					for i in 3:
						_cockpit.stickers.set_tier(i, 0)
					_main.sfx.play("ui_ok")


func _default_on(row: String) -> bool:
	return row in ["fullscreen", "ghost_on"]


func _draw_settings() -> void:
	draw_rect(Rect2(Vector2.ZERO, GRID), COL_SHADE)
	_draw_panel(Rect2(Vector2(220.0, 30.0), Vector2(520.0, 500.0)))
	_text_center(Loc.t("设置"), 44.0 + 32.0, 32, COL_GOLD)
	for i in SET_ROWS.size():
		var y := 96.0 + 38.0 * i
		var row := SET_ROWS[i]
		var sel := i == _set_sel
		if row == "clear":
			var label := Loc.t("再按一次回车确认") if _clear_armed else Loc.t(SET_ROW_NAMES[i])
			_draw_button(label, Vector2(480.0, y), sel, true)
			continue
		draw_string(_font, Vector2(250.0, y + 26.0), Loc.t(SET_ROW_NAMES[i]), HORIZONTAL_ALIGNMENT_LEFT, 250.0, 20, COL_TEXT)
		var box := Rect2(Vector2(530.0, y), Vector2(180.0, 34.0))
		draw_rect(box, COL_TEXT)
		draw_rect(box.grow(-4.0), COL_GOLD if sel else COL_DARK)
		var ink := COL_DARK if sel else COL_TEXT
		if row.begins_with("vol_"):
			var v := int(SaveData.data.get(row, 8))
			for k in 10:
				var cell := Rect2(Vector2(box.position.x + 14.0 + k * 15.5, y + 9.0), Vector2(11.0, 18.0))
				if k < v:
					draw_rect(cell, ink)
				else:
					draw_rect(cell, ink, false, 1.0)
		else:
			var word := ""
			if row == "lang":
				word = "中文" if Loc.lang() == "zh" else "English"
			elif row == "fx_level":
				word = Loc.t(FX_LEVEL_NAMES[clampi(int(SaveData.data.get("fx_level", 0)), 0, 2)])
			else:
				var on := bool(SaveData.data.get(row, _default_on(row)))
				word = (Loc.t("自动") if on else Loc.t("手动")) if row == "auto_shift" else (Loc.t("开") if on else Loc.t("关"))
			draw_string(_font, Vector2(box.position.x, y + 26.0), word, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 20, ink)
		if sel:
			var tip := Vector2(232.0, y + 18.0)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(8.0, 0.0), tip + Vector2(-6.0, -8.0), tip + Vector2(-6.0, 8.0)]), COL_RED)
	draw_string(_font, Vector2(0.0, 506.0 + 12.0), Loc.t("↑ ↓ 选择   ← → 调整   回车 切换   Esc 返回"), HORIZONTAL_ALIGNMENT_CENTER, GRID.x, 12, COL_DIM)


# ───────────────────────── 邀请函与开场字幕（9.3） ─────────────────────────

func play_intro() -> void:
	state = State.INVITE
	_main.sfx.play("comm")


func _intro_text(i: int) -> String:
	var line := Loc.t(INTRO_LINES[i])
	match i:
		3: return line % ["[%s]" % SaveData.key_label("brake"), "[%s]" % SaveData.key_label("shift_down")]
		4: return line % ("[%s]" % SaveData.key_label("throttle"))
	return line


func _intro_advance() -> void:
	if state == State.INVITE:
		state = State.INTRO
		_intro_line = 0
		show_caption("CEO", _intro_text(0), -1.0, true)
		return
	_intro_line += 1
	if _intro_line < INTRO_LINES.size():
		show_caption("CEO", _intro_text(_intro_line), -1.0, true)
	else:
		hide_caption()
		SaveData.data["intro_seen"] = true
		SaveData.save()
		enter_ignite()


func _draw_invite() -> void:
	draw_rect(Rect2(Vector2.ZERO, GRID), COL_DARKER)
	var r := Rect2(Vector2(180.0, 80.0), Vector2(600.0, 380.0))
	draw_rect(Rect2(r.position + Vector2(6.0, 6.0), r.size), COL_RED)
	draw_rect(r, COL_DARK)
	draw_rect(r.grow(-4.0), COL_TEXT)
	draw_string(_font, Vector2(r.position.x, 104.0 + 36.0), Loc.t("邀请函"), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 36, COL_RED)
	var lines := [[170.0, Loc.t("致地球上最快的人：")], [214.0, Loc.t("我们造了一台车。")], [248.0, Loc.t("它用了不属于这颗星球的技术。")],
			[282.0, Loc.t("能驾驭它的人，全世界只有一个。")], [326.0, Loc.t("请来试车。")]]
	for l: Array in lines:
		draw_string(_font, Vector2(220.0, float(l[0]) + 24.0), str(l[1]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, COL_DARK)
	draw_string(_font, Vector2(0.0, 390.0 + 24.0), Loc.t("—— 星速计划"), HORIZONTAL_ALIGNMENT_RIGHT, 740.0, 24, COL_RED)
	if _blink < 0.5:
		_text_center(Loc.t("按 [%s] 继续") % SaveData.key_label("throttle"), 484.0 + 12.0, 12, COL_DIM)


# ───────────────────────── 标题画面与点火 ─────────────────────────

## 标题画面的按钮：[文字, 可用, 动作]。键位设置、语言、重看开场在后面的功能里接上。
func title_buttons() -> Array:
	var list := [[Loc.t("开始"), true, "start"]]
	list.append([Loc.t("怎么玩"), true, "help"])
	list.append([Loc.t("设置"), true, "settings"])
	list.append([Loc.t("键位设置"), true, "keys"])
	if bool(SaveData.data.get("intro_seen", false)):
		list.append([Loc.t("重看开场"), true, "intro"])
	list.append([Loc.t("制作人员"), true, "credits"])
	list.append([Loc.t("退出"), true, "quit"])
	return list


## 回到标题画面：世界画面不显示，座舱漆黑，转速表微光，贴纸被小灯照亮（6.8）。
func enter_title() -> void:
	state = State.TITLE
	_title_select = 0
	_car.use_device_input = false
	_car.place(Track.PATH_ACCESS, 0.0, 0.0, 1, true)
	_car.mode = CarSim.Mode.LOCKED
	_main.call("clear_section_time")
	_main.call("set_ignited_look", false)
	_update_hint()


## 点火提示（9.3）：长按油门 T-50 秒点火。
func enter_ignite() -> void:
	state = State.IGNITE
	_ignite_hold = 0.0
	_need_release = Input.is_action_pressed("throttle")
	_update_hint()


func _update_ignite(delta: float) -> void:
	var held := Input.is_action_pressed("throttle")
	if _need_release:
		_need_release = held
		return
	if held:
		if _ignite_hold == 0.0:
			_main.sfx.play("starter")
		_ignite_hold += delta
		var p := clampf(_ignite_hold / Tuning.d.t50_ignition_hold, 0.0, 1.0)
		_cockpit.needle_override = p * Cockpit.RPM_MAX
		# 转速表 30% 的微光下指针几乎看不见；长按期间表随充能亮起来，让进度看得清
		_cockpit.set_tach_brightness(lerpf(TACH_DARK, 1.0, sqrt(p)))
		if _ignite_hold >= Tuning.d.t50_ignition_hold:
			_start_ignition()
	elif _ignite_hold > 0.0:
		# 没按满就松手：计时清零，指针落回 0
		_ignite_hold = 0.0
		_cockpit.needle_override = 0.0
		_cockpit.set_tach_brightness(TACH_DARK)
		_main.sfx.stop("starter")


func _start_ignition() -> void:
	state = State.IGNITING
	_ignite_time = 0.0
	_need_release = true
	_main.sfx.stop("starter")
	_cockpit.needle_override = -1.0
	_main.call("set_drive_audio_on", true)
	_main.engine_audio.rev_target = START_BLIP_RPM     # 点着的那一下：短促地轰一声再落到怠速
	_car.ignited.emit()


func _update_igniting(delta: float) -> void:
	_ignite_time += delta
	if _ignite_time >= START_BLIP_TIME:
		_main.engine_audio.rev_target = -1.0
	var light := clampf((_ignite_time - LIGHT_UP_FROM) / (LIGHT_UP_TO - LIGHT_UP_FROM), 0.0, 1.0)
	_main.cockpit_brightness = lerpf(COCKPIT_DARK, 1.0, light)
	if _ignite_time >= REVEAL_START:
		_main.call("set_world_reveal", clampf((_ignite_time - REVEAL_START) / REVEAL_TIME, 0.0, 1.0))
	if not Input.is_action_pressed("throttle"):
		_need_release = false
	if _ignite_time >= IGNITE_TIME and not _need_release:
		_main.call("set_ignited_look", true)
		enter_base()


func _title_choose() -> void:
	var b: Array = title_buttons()[_title_select]
	if not bool(b[1]):
		return
	_main.sfx.play("ui_ok")
	match str(b[2]):
		"start":
			if not bool(SaveData.data.get("intro_seen", false)):
				play_intro()
			else:
				enter_ignite()
		"keys":
			open_keys()
		"settings":
			open_settings()
		"credits":
			_credits_open = true
		"help":
			_help_open = true
		"intro":
			play_intro()
		"lang":
			Loc.toggle()
		"quit":
			SaveData.save()
			get_tree().quit()


func _title_move(step: int) -> void:
	var list := title_buttons()
	for _i in list.size():
		_title_select = posmod(_title_select + step, list.size())
		if bool(list[_title_select][1]):
			break
	_main.sfx.play("ui_move")


# ───────────────────────── 结尾（6.7、9.9） ─────────────────────────

func _update_ending(delta: float) -> void:
	_end_t += delta
	var t := _end_t
	if _end_steps_done == 0:
		# 1. 1.0 秒白化，引擎声在这 1.0 秒内淡出
		_main.whiteout = clampf(t / END_WHITE, 0.0, 1.0)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Engine"), linear_to_db(maxf(1.0 - t / END_WHITE, 0.001)))
		if t >= END_WHITE:
			_end_steps_done = 1
			# 2. 白化结束：车停在车库里，座舱视角，世界画面正常显示
			_main.call("ending_in_garage")
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Engine"), 0.0)
	if _end_steps_done >= 1:
		# 3. 座舱摄像机 1.5 秒内抬向贴纸，视野收到 40°，贴纸放大到 1.5 倍（smoothstep）
		var k := smoothstep(0.0, 1.0, (t - END_WHITE) / END_TURN)
		_main.camera_rig.ending_look = k
		_cockpit.stickers.zoom = lerpf(1.0, 1.5, k)
	var t_sweep := END_WHITE + END_TURN
	if _end_steps_done == 1 and t >= t_sweep:
		_end_steps_done = 2
		_cockpit.stickers.sweep(0)
		_main.sfx.play("shine")
		show_caption("CEO", Loc.t(END_CAPTION), END_CAPTION_TIME)   # 4. 结尾面板和 CEO 字幕
	if _end_steps_done == 2 and t >= t_sweep + END_SWEEP_GAP:
		_end_steps_done = 3
		_cockpit.stickers.sweep(1)
		_main.sfx.play("shine")
	if _end_steps_done == 3 and t >= t_sweep + END_SWEEP_GAP * 2.0:
		_end_steps_done = 4
		var last := section_medals.size() - 1
		if section_times[last] >= 0.0 and section_medals[last] > int(_start_medals[last]):
			_cockpit.stickers.set_tier(last, section_medals[last], true)
			_main.sfx.play("sticker")
		else:
			_cockpit.stickers.sweep(last)
			_main.sfx.play("shine")


func _leave_ending() -> void:
	_main.camera_rig.ending_look = 0.0
	_cockpit.stickers.zoom = 1.0
	_main.whiteout = -1.0
	_main.sfx.play("ui_ok")
	_main.call("return_to_base")


func _draw_ending() -> void:
	if _end_steps_done < 2:
		return
	var p := Vector2(60.0, 150.0)
	_draw_panel(Rect2(p, Vector2(480.0, 286.0)))
	draw_string(_font, Vector2(p.x + 20.0, 166.0 + 36.0), Loc.t("绕地球一圈，完成"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36, COL_GOLD)
	if new_record and fposmod(_end_t, 0.6) < 0.4:
		draw_string(_font, Vector2(p.x, 138.0), Loc.t("新纪录！"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, COL_RECORD)
	var y := 230.0
	for i in section_times.size():
		var x := p.x + 20.0
		draw_string(_font, Vector2(x, y + 24.0), Loc.t(_track.section_names[i]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, COL_TEXT)
		var mine: float = section_times[i]
		draw_string(_font, Vector2(x + 80.0, y + 24.0), format_time(mine), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24,
				COL_RECORD if section_records[i] else COL_TEXT)
		if mine >= 0.0:
			draw_string(_font, Vector2(x + 220.0, y + 24.0), Loc.t(StickerDisplay.TIER_NAMES[section_medals[i]] + "牌"),
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, COL_TEXT)
			if section_medals[i] > int(_start_medals[i]):
				draw_string(_font, Vector2(x + 300.0, y + 22.0), Loc.t("新纪录"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_RED)
		y += 36.0
	# 本局统计
	var c: Array = _main.corner_judge.counts
	var stats := Loc.t("完美过弯") + " %d / %d    " % [c[0], c[2]] + Loc.t("撞车") + " %d    " % run_crashes 			+ Loc.t("最高") + " %d km/h" % roundi(run_top_kmh)
	draw_string(_font, Vector2(p.x + 20.0, 356.0), stats, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, COL_DIM)
	if not section_times.has(-1.0):
		draw_string(_font, Vector2(p.x + 20.0, 392.0), Loc.t("总用时"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, COL_TEXT)
		draw_string(_font, Vector2(p.x + 100.0, 392.0), format_time(total_time()), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16,
				COL_RECORD if new_record else COL_TEXT)
		if not new_record:
			draw_string(_font, Vector2(p.x + 220.0, 392.0), Loc.t("最好 ") + format_time(float(SaveData.data.get("best_total", -1.0))),
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_DIM)
		if run_rank > 0:
			draw_string(_font, Vector2(p.x + 340.0, 392.0), Loc.t("本地排行 第 %d") % run_rank, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_GOLD)
	if _blink < 0.5:
		draw_string(_font, Vector2(p.x + 20.0, 422.0), Loc.t("回车 回大本营"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_DIM)


## 9.6 的贴纸文字面板：280×84。规格的位置 (590, 215) 会压住第三枚贴纸（贴纸的位置和规格示意图不同），往左挪到 (540, 215)。
func _draw_medal_panel() -> void:
	var index: int = _medal_panel[0]
	var tier: int = _medal_panel[1]
	var r := Rect2(Vector2(540.0, 215.0), Vector2(280.0, 84.0))
	_draw_panel(r)
	var x := r.position.x + 12.0
	draw_string(_font, Vector2(x, r.position.y + 10.0 + 22.0), "%s  %s" % [Loc.t(_track.section_names[index]), Loc.t(StickerDisplay.TIER_NAMES[tier] + "牌")],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, COL_GOLD)
	draw_string(_font, Vector2(x, r.position.y + 40.0 + 11.0), Loc.t("用时 ") + format_time(float(_medal_panel[2])),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_TEXT)
	var line3 := Loc.t("最高等级")
	if tier < 4:
		var th: PackedFloat32Array = [Tuning.d.t53_forest_thresholds, Tuning.d.t53_ice_thresholds, Tuning.d.t53_city_thresholds][index]
		line3 = Loc.t("金牌 %s 以内") % format_time(th[0])
	draw_string(_font, Vector2(x, r.position.y + 58.0 + 11.0), line3, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_DIM)
	if bool(_medal_panel[3]):
		var w := _font.get_string_size(line3, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x
		draw_string(_font, Vector2(x + w, r.position.y + 58.0 + 11.0), Loc.t("  新纪录"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_RED)


## 9.1 的面板：深蓝黑填充，4 像素金黄边框，(4, 4) 更深蓝黑硬投影。
func _draw_panel(r: Rect2, border := COL_GOLD, fill := COL_DARK) -> void:
	draw_rect(Rect2(r.position + Vector2(4.0, 4.0), r.size), COL_DARKER)
	draw_rect(r, border)
	draw_rect(r.grow(-4.0), fill)


# ───────────────────────── 字幕条（9.3） ─────────────────────────

## 显示一条字幕；seconds < 0 = 一直显示到被替换或 hide_caption；wait_key = 右下角显示推进提示 ▼。
func show_caption(speaker: String, text: String, seconds: float, wait_key := false) -> void:
	caption_speaker = speaker
	caption_text = text
	caption_left = seconds
	caption_wait_key = wait_key
	_main.sfx.play("comm")


func hide_caption() -> void:
	caption_text = ""


func _update_caption(delta: float) -> void:
	if caption_text != "" and caption_left > 0.0:
		caption_left -= delta
		if caption_left <= 0.0:
			caption_text = ""


func _draw_caption() -> void:
	if caption_text == "":
		return
	var r := Rect2(Vector2(120.0, 44.0), Vector2(720.0, 76.0))
	_draw_panel(r)
	if caption_speaker != "":
		var w := _font.get_string_size(caption_speaker, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x
		draw_rect(Rect2(Vector2(128.0, 26.0), Vector2(w + 8.0, 18.0)), COL_GOLD)
		draw_string(_font, Vector2(132.0, 40.0), caption_speaker, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_DARK)
	draw_multiline_string(_font, Vector2(136.0, 54.0 + 22.0), caption_text, HORIZONTAL_ALIGNMENT_LEFT, 690.0, 24, 2, COL_TEXT)
	if caption_wait_key and _blink < 0.5:
		draw_string(_font, Vector2(816.0, 112.0), "▼", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_GOLD)


# ───────────────────────── 状态切换 ─────────────────────────

## 回大本营：车放回车库，停住，等玩家选。
func enter_base() -> void:
	if state in [State.RUN, State.PRACTICE, State.RESULTS, State.ENDING]:
		SaveData.save()          # 累计统计在回大本营时落盘
	state = State.BASE
	_select = 0
	section_times = [-1.0, -1.0, -1.0]
	section_records = [false, false, false]
	section_medals = [0, 0, 0]
	new_record = false
	_car.use_device_input = true
	_car.set_exit_armed(false)
	_car.place(Track.PATH_ACCESS, 0.0, 0.0, 1, true)
	_car.mode = CarSim.Mode.LOCKED
	_main.call("clear_section_time")
	_update_hint()


func _leave_base() -> void:
	_start_medals = (SaveData.data.get("best_medals", [0, 0, 0]) as Array).duplicate()
	if _select >= 1 and _select <= 3:
		_main.call("restart_run", _select - 1)     # 单区段：直接放到那个区段的起点线前
		return
	single_section = -1
	var to_main := _select == 0
	if to_main:
		SaveData.stat_add("runs", 1)
	_car.set_exit_armed(to_main)
	_car.mode = CarSim.Mode.DRIVE
	state = State.RUN if to_main else State.PRACTICE
	_main.corner_judge.reset_counts()
	_reset_run_stats()
	if not to_main:
		_main.tutorial.start()
	_update_hint()


# ───────────────────────── 区段标题卡（开发者 2026-11-19 第 2 轮 #1） ─────────────────────────
## 过区段起点线（开始计时）时，挡风玻璃上方滑入"第 N 区段 · 名字"，下面一行是这个区段的最好成绩和下一枚奖牌的目标。

const BANNER_TIME := 2.6
var _banner_t := -1.0
var _banner_index := 0


func section_banner(index: int) -> void:
	if state != State.RUN:
		return
	_banner_index = index
	_banner_t = 0.0
	_main.sfx.play("shine", -6.0)


func _draw_banner() -> void:
	if _banner_t < 0.0 or state != State.RUN or paused:
		return
	var t := _banner_t
	var slide := clampf(t / 0.25, 0.0, 1.0)
	var alpha := clampf((BANNER_TIME - t) / 0.4, 0.0, 1.0)
	var x := lerpf(-260.0, 0.0, 1.0 - pow(1.0 - slide, 3.0))
	var r := Rect2(Vector2(330.0 + x, 96.0), Vector2(300.0, 66.0))
	draw_rect(Rect2(r.position + Vector2(4.0, 4.0), r.size), Color(COL_DARKER, 0.8 * alpha))
	draw_rect(r, Color(COL_GOLD, alpha))
	draw_rect(r.grow(-3.0), Color(COL_DARK, alpha))
	var title := Loc.t("第 %d 区段") % (_banner_index + 1) + " · " + Loc.t(_track.section_names[_banner_index])
	draw_string(_font, Vector2(r.position.x, r.position.y + 32.0), title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, Color(COL_GOLD, alpha))
	var best: Array = SaveData.data.get("best_sections", [-1.0, -1.0, -1.0])
	var sub := ""
	if float(best[_banner_index]) >= 0.0:
		sub = Loc.t("最好") + " " + format_time(float(best[_banner_index]))
	var medals: Array = SaveData.data.get("best_medals", [0, 0, 0])
	var tier := int(medals[_banner_index])
	if tier < 4:
		var th: PackedFloat32Array = [Tuning.d.t53_forest_thresholds, Tuning.d.t53_ice_thresholds, Tuning.d.t53_city_thresholds][_banner_index]
		var next := maxi(tier + 1, 2)
		sub += ("    " if sub != "" else "") + Loc.t(StickerDisplay.TIER_NAMES[next]) + " ≤ " + format_time(th[4 - next])
	draw_string(_font, Vector2(r.position.x, r.position.y + 54.0), sub, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, Color(COL_TEXT, alpha))


## 一键重开（main.restart_run 摆好车之后调用）：清空本局成绩，进入计时赛。
func restart_state(section := -1) -> void:
	single_section = section
	SaveData.stat_add("runs", 1)
	if paused:
		_set_paused(false)
	_start_medals = (SaveData.data.get("best_medals", [0, 0, 0]) as Array).duplicate()
	section_times = [-1.0, -1.0, -1.0]
	section_records = [false, false, false]
	section_medals = [0, 0, 0]
	new_record = false
	_medal_panel_t = -1.0
	_main.tutorial.stop()
	_main.corner_judge.reset_counts()
	_reset_run_stats()
	state = State.RUN
	_update_hint()


func _reset_run_stats() -> void:
	run_crashes = 0
	run_top_kmh = 0.0


## 暂停菜单这一次显示哪些项（序号对应 PAUSE_OPTIONS）。
func _pause_items() -> Array[int]:
	var items: Array[int] = []
	for i in PAUSE_OPTIONS.size():
		if i == PAUSE_RESTART and state != State.RUN:
			continue
		items.append(i)
	return items


## 调试用（F4 瞬移到区段起点）：直接进入计时赛状态；没跑过的区段没有成绩，结算时不记纪录。
func debug_enter_run() -> void:
	if state != State.RUN:
		_start_medals = (SaveData.data.get("best_medals", [0, 0, 0]) as Array).duplicate()
		section_times = [-1.0, -1.0, -1.0]
		section_records = [false, false, false]
		section_medals = [0, 0, 0]
	state = State.RUN
	_car.use_device_input = true
	_update_hint()


## 主场景在车过区段终点线时调用。
func section_done(index: int, seconds: float) -> void:
	if state != State.RUN or index < 0 or index >= section_times.size():
		return
	section_times[index] = seconds
	# 是否刷新了这个区段的历史最好；刷新了就立刻存档
	var best_sections: Array = SaveData.data.get("best_sections", [-1.0, -1.0, -1.0])
	var old_best := float(best_sections[index])
	var record := old_best < 0.0 or seconds < old_best
	section_records[index] = record
	if record:
		best_sections[index] = seconds
		SaveData.data["best_sections"] = best_sections
		SaveData.save()
	# R-32 / R-33：按 T-53 评贴纸等级；高于存档里的最高等级就存档，挡风玻璃上的贴纸换掉并弹一下
	var tier := medal_for(index, seconds)
	section_medals[index] = tier
	var medals: Array = SaveData.data.get("best_medals", [0, 0, 0])
	var improved := tier > int(medals[index])
	if improved:
		medals[index] = tier
		SaveData.data["best_medals"] = medals
		SaveData.save()
	if tier >= 4:
		Achievements.unlock("gold")
	if int(medals[0]) >= 4 and int(medals[1]) >= 4 and int(medals[2]) >= 4:
		Achievements.unlock("all_gold")
	if index < section_times.size() - 1:
		# 9.6：森林、冰原的贴纸在越过终点线时出现，不暂停驾驶；城市的贴纸在结尾画面里贴（6.7）
		_main.sfx.play("sticker")
		if improved:
			_cockpit.stickers.set_tier(index, tier, true)
		else:
			_cockpit.stickers.sweep(index)
		_medal_panel_t = 0.0
		_medal_panel = [index, tier, seconds, improved]
	if record and old_best >= 0.0:
		_celebrate(Loc.t("区段新纪录") + "  " + format_delta(seconds - old_best))
	recent.append({"name": _track.section_names[index], "time": seconds, "record": record,
			"diff": seconds - old_best if old_best >= 0.0 else NAN})
	while recent.size() > RECENT_COUNT:
		recent.pop_front()
	if single_section >= 0:
		if index == single_section:
			_finish_single()
		return
	if index == section_times.size() - 1:
		_finish_run()


## 单区段跑完：车自己刹停，显示结算（回车回大本营，R 再跑一次这一段）。
func _finish_single() -> void:
	SaveData.stat_add("finished", 1)
	SaveData.save()
	state = State.RESULTS
	_medal_panel_t = -1.0
	_car.use_device_input = false
	_car.set_throttle(false)
	_car.brake = true
	_main.sfx.play("sticker")
	_update_hint()


func _finish_run() -> void:
	state = State.ENDING
	_end_t = 0.0
	_end_steps_done = 0
	_main.sfx.play("whiteout")
	# 结算时车自己刹停在终点线后的尾段上
	_car.use_device_input = false
	_car.set_throttle(false)
	_car.brake = true
	new_record = false
	var complete := not section_times.has(-1.0)
	run_rank = 0
	SaveData.stat_add("finished", 1)
	if complete:
		var total := total_time()
		var best_total := float(SaveData.data.get("best_total", -1.0))
		if best_total < 0.0 or total < best_total:
			SaveData.data["best_total"] = total
			new_record = true
			if best_total >= 0.0:
				_main.sfx.play("record")
		run_rank = _add_top_run(total)
		Achievements.unlock("finish")
		if run_crashes == 0:
			Achievements.unlock("clean")
		if total < 240.0:
			Achievements.unlock("sub4")
		var c: Array = _main.corner_judge.counts
		if int(c[2]) > 0 and int(c[0]) == int(c[2]):
			Achievements.unlock("perfect_all")
	SaveData.save()
	_update_hint()


## 奖牌和最好成绩对齐（开发者 2026-11-19 第 1 轮 #9 发现）：门槛重新校准过，存档里的奖牌是按旧门槛评的，
## 会出现"最好成绩已经够金牌、贴纸还是银牌"。启动时按现在的门槛重评最好成绩，只升不降。
static func sync_medals() -> void:
	var best: Array = SaveData.data.get("best_sections", [-1.0, -1.0, -1.0])
	var medals: Array = SaveData.data.get("best_medals", [0, 0, 0])
	var changed := false
	for i in mini(best.size(), medals.size()):
		if float(best[i]) >= 0.0:
			var tier := medal_for(i, float(best[i]))
			if tier > int(medals[i]):
				medals[i] = tier
				changed = true
	if changed:
		SaveData.data["best_medals"] = medals
		SaveData.save()


## T-53：用时 ≤ 金 / 银 / 铜门槛分别是 4 / 3 / 2，跑完但更慢是 1（塑料）。
static func medal_for(index: int, seconds: float) -> int:
	var t := Tuning.d
	var th: PackedFloat32Array = [t.t53_forest_thresholds, t.t53_ice_thresholds, t.t53_city_thresholds][index]
	for k in 3:
		if seconds <= th[k]:
			return 4 - k
	return 1


## 本地排行（开发者 2026-11-19 第 2 轮 #4）：存三段连跑的总用时前 5（存档 top_runs：[{t, date}]）。返回名次，没进前 5 是 0。
func _add_top_run(total: float) -> int:
	var runs: Array = SaveData.data.get("top_runs", [])
	# 排行是这个功能之后才有的：第一次写入时把之前的最好总成绩补进去（日期未知）
	if runs.is_empty() and float(SaveData.data.get("best_total", -1.0)) >= 0.0 and float(SaveData.data["best_total"]) < total:
		runs.append({"t": float(SaveData.data["best_total"]), "date": "—"})
	var d := Time.get_date_dict_from_system()
	var entry := {"t": total, "date": "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]}
	runs.append(entry)
	runs.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var rank := runs.find(entry) + 1
	runs = runs.slice(0, TOP_RUNS)
	SaveData.data["top_runs"] = runs
	return rank if rank <= TOP_RUNS else 0


## 累计统计（开发者 2026-11-19 第 2 轮 #10）：大本营信息区第 3 页。
func _stats_lines() -> Array:
	var st: Dictionary = SaveData.data.get("stats", {})
	var play := int(float(st.get("play_s", 0.0)))
	return [Loc.t("累计统计"),
		Loc.t("驾驶") + " %.1f km    " % float(st.get("km", 0.0)) + Loc.t("时间") + " %d:%02d:%02d" % [play / 3600, play / 60 % 60, play % 60],
		Loc.t("出发") + " %d    " % int(st.get("runs", 0)) + Loc.t("跑完") + " %d    " % int(st.get("finished", 0)) + Loc.t("撞车") + " %d" % int(st.get("crashes", 0)),
		Loc.t("完美过弯") + " %d    " % int(st.get("perfect", 0)) + Loc.t("最高车速") + " %d km/h" % roundi(float(st.get("top_kmh", 0.0)))]


func _top_lines() -> Array:
	var lines := [Loc.t("本地排行（三段连跑总用时）")]
	var runs: Array = SaveData.data.get("top_runs", [])
	if runs.is_empty():
		var bt := float(SaveData.data.get("best_total", -1.0))
		lines.append(Loc.t("还没有记录") if bt < 0.0 else "1.  " + format_time(bt))
	for i in runs.size():
		lines.append("%d.  %s    %s" % [i + 1, format_time(float(runs[i]["t"])), str(runs[i]["date"])])
	return lines


func total_time() -> float:
	var sum := 0.0
	for t in section_times:
		if t >= 0.0:
			sum += t
	return sum


func _update_hint() -> void:
	_hint.visible = state == State.PRACTICE
	_hint.text = Loc.t("练习环道    回车：回大本营")


# ───────────────────────── 输入 ─────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _credits_open or _help_open:
		if event.is_action_pressed("pause") or event.is_action_pressed("confirm"):
			_credits_open = false
			_help_open = false
			_main.sfx.play("ui_back")
		get_viewport().set_input_as_handled()
		return
	if _set_open:
		_settings_input(event)
		get_viewport().set_input_as_handled()
		return
	if _keys_open:
		_keys_input(event)
		get_viewport().set_input_as_handled()
		return
	if state == State.ENDING:
		# 结尾时 Esc 不响应；面板出来后回车回大本营
		if event.is_action_pressed("confirm") and _end_steps_done >= 2:
			_leave_ending()
		return
	if state in [State.INVITE, State.INTRO]:
		if event.is_action_pressed("throttle") and not event.is_echo():
			_intro_advance()
		return
	if state in [State.TITLE, State.IGNITE, State.IGNITING]:
		# 9.1 / 11.2a：标题、点火提示时 Esc 不响应
		if state == State.TITLE:
			if event.is_action_pressed("ui_up"):
				_title_move(-1)
			elif event.is_action_pressed("ui_down"):
				_title_move(1)
			elif event.is_action_pressed("confirm"):
				_title_choose()
		return
	if event.is_action_pressed("pause"):
		_set_paused(not paused)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("restart") and (state == State.RUN or (state == State.RESULTS and single_section >= 0)) and not paused:
		_main.call("restart_run", maxi(single_section, 0) if single_section >= 0 else -1)
		get_viewport().set_input_as_handled()
		return
	if paused:
		var n := _pause_items().size()
		if event.is_action_pressed("ui_up"):
			_pause_select = posmod(_pause_select - 1, n)
		elif event.is_action_pressed("ui_down"):
			_pause_select = posmod(_pause_select + 1, n)
		elif event.is_action_pressed("confirm"):
			_pause_choose()
		get_viewport().set_input_as_handled()
		return
	match state:
		State.BASE:
			if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
				_base_page = posmod(_base_page + (1 if event.is_action_pressed("ui_right") else -1), BASE_PAGES)
				_main.sfx.play("ui_move")
			elif event.is_action_pressed("ui_up"):
				_select = posmod(_select - 1, BASE_OPTIONS.size())
			elif event.is_action_pressed("ui_down"):
				_select = posmod(_select + 1, BASE_OPTIONS.size())
			elif event.is_action_pressed("confirm"):
				_leave_base()
		State.PRACTICE, State.RESULTS:
			if event.is_action_pressed("confirm"):
				_main.call("return_to_base")
		State.ENDING:
			if event.is_action_pressed("confirm") and _end_steps_done >= 2:
				_leave_ending()


## 窗口失去焦点（切到别的程序）时自动暂停（开发者 2026-11-19 第 2 轮 #8）：只在驾驶中。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveData.save()          # 关窗口时把累计统计存下来
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not paused and state in [State.RUN, State.PRACTICE] 			and not _keys_open and not _set_open:
		_set_paused(true)


func _set_paused(on: bool) -> void:
	paused = on
	_pause_select = 0
	get_tree().paused = on
	AudioServer.set_bus_mute(0, on)       # 暂停时所有声音静音（循环声不会自己停）


func _pause_choose() -> void:
	match PAUSE_OPTIONS[_pause_items()[_pause_select]]:
		"继续":
			_set_paused(false)
		"重新开始":
			_main.call("restart_run", single_section)
		"设置":
			open_settings()
		"键位设置":
			open_keys()
		"回大本营":
			_set_paused(false)
			_main.call("return_to_base")
		"回到标题":
			_set_paused(false)
			_main.call("return_to_title")
		"退出游戏":
			SaveData.save()
			get_tree().quit()


# ───────────────────────── 界面 ─────────────────────────

func _process(delta: float) -> void:
	_blink = fposmod(_blink + delta, 1.0)
	if not paused:
		_update_caption(delta)
		if state == State.RUN:
			run_top_kmh = maxf(run_top_kmh, _car.v / CarSim.KMH)
		_update_lap(delta)
		if state in [State.RUN, State.PRACTICE]:
			if _car.v / CarSim.KMH >= Tuning.d.top_speed_kmh - 0.5:
				Achievements.unlock("top")
			if state == State.RUN and int(_main.corner_judge.counts[0]) >= 10:
				Achievements.unlock("perfect10")
			if float(SaveData.data["stats"].get("km", 0.0)) >= 100.0:
				Achievements.unlock("km100")
			if bool(SaveData.data.get("tutorial_done", false)):
				Achievements.unlock("tutorial")
			SaveData.stat_add("km", _car.v * delta / 1000.0)
			SaveData.stat_add("play_s", delta)
			SaveData.stat_max("top_kmh", _car.v / CarSim.KMH)
		_update_toast(delta)
		if _celebrate_t >= 0.0:
			_celebrate_t += delta
			if _celebrate_t >= CELEBRATE_TIME:
				_celebrate_t = -1.0
		if _banner_t >= 0.0:
			_banner_t += delta
			if _banner_t >= BANNER_TIME:
				_banner_t = -1.0
		if _medal_panel_t >= 0.0:
			_medal_panel_t += delta
			if _medal_panel_t >= 2.5:
				_medal_panel_t = -1.0
		if state == State.ENDING:
			_update_ending(delta)
		if state == State.IGNITE:
			_update_ignite(delta)
		elif state == State.IGNITING:
			_update_igniting(delta)
	queue_redraw()


func _draw() -> void:
	_draw_frame()
	_draw_caption()
	if _keys_open:
		_draw_keys()
	if _set_open:
		_draw_settings()
	if _credits_open:
		_draw_credits()
	if _help_open:
		_draw_help()


func _draw_frame() -> void:
	if state == State.INVITE:
		_draw_invite()
		return
	if state == State.ENDING:
		_draw_ending()
		return
	if state == State.TITLE:
		_draw_title()
		return
	if state == State.IGNITE:
		# 点火提示：居中 y = 290，金黄，每秒闪一次；长按期间常亮
		if _ignite_hold > 0.0 or _blink < 0.5:
			_text_center(Loc.t("长按 [%s] 点火") % SaveData.key_label("throttle"), 290.0, 24, COL_GOLD)
		return
	if state == State.IGNITING:
		return
	if paused:
		var opts: Array[String] = []
		for i in _pause_items():
			opts.append(PAUSE_OPTIONS[i])
		var foot := Loc.t("↑ ↓ 选择    回车 确定    Esc 继续")
		if state == State.RUN:
			foot += Loc.t("    R 重新开始")
		_draw_menu("暂停", opts, _pause_select, foot, [])
	elif state == State.BASE:
		var pages := [_best_lines(), _top_lines(), _stats_lines(), _achievement_lines()]
		_draw_menu("大本营", BASE_OPTIONS, _select, Loc.t("↑ ↓ 选择    回车 出发    ← → 奖牌 / 排行 / 统计 / 成就"), pages[_base_page])
	elif state == State.RESULTS:
		_draw_results()
	if not paused and state != State.BASE:
		_draw_recent()
	if _medal_panel_t >= 0.3 and state == State.RUN:
		_draw_medal_panel()
	_draw_rail_glow()
	_draw_laps()
	_draw_celebrate()
	_draw_achievement_toast()
	_draw_corner_popup()
	_draw_banner()
	_draw_speedo()


# ───────────────────────── 刷新纪录的庆祝（第 3 轮 #4） ─────────────────────────
## 区段刷新纪录：紫色大字"区段新纪录 −1.23"从中间放大弹出，琶音；结尾刷新总纪录：面板上方紫色"新纪录！"闪烁。

const CELEBRATE_TIME := 2.2
var _celebrate_text := ""
var _celebrate_t := -1.0


func _celebrate(text: String) -> void:
	_celebrate_text = text
	_celebrate_t = 0.0
	_main.sfx.play("record")


func _draw_celebrate() -> void:
	if _celebrate_t < 0.0 or paused:
		return
	var t := _celebrate_t
	var scale := 1.0 + 0.6 * exp(-t * 10.0)
	var alpha := clampf((CELEBRATE_TIME - t) / 0.5, 0.0, 1.0)
	var size := int(30.0 * scale)
	_text_center(_celebrate_text, 214.0 + 2.0, size, Color(COL_DARKER, alpha), Vector2(2.0, 0.0))
	_text_center(_celebrate_text, 214.0, size, Color(COL_RECORD, alpha))


# ───────────────────────── 成就提示（第 3 轮 #3） ─────────────────────────

const TOAST_TIME := 3.2
var _toast_id := ""
var _toast_t := 0.0


func _update_toast(delta: float) -> void:
	if _toast_id != "":
		_toast_t += delta
		if _toast_t >= TOAST_TIME:
			_toast_id = ""
	if _toast_id == "" and not Achievements.pending.is_empty() and state != State.ENDING:
		_toast_id = Achievements.pending.pop_front()
		_toast_t = 0.0
		_main.sfx.play("sticker", -3.0)


## 屏幕上方正中从上面滑下来："成就解锁 · 名字"，下面一行说明。
func _draw_achievement_toast() -> void:
	if _toast_id == "":
		return
	var a := Achievements.info(_toast_id)
	var drop := clampf(_toast_t / 0.25, 0.0, 1.0)
	var alpha := clampf((TOAST_TIME - _toast_t) / 0.4, 0.0, 1.0)
	var r := Rect2(Vector2(300.0, lerpf(-70.0, 14.0, 1.0 - pow(1.0 - drop, 3.0))), Vector2(360.0, 58.0))
	draw_rect(r, Color(COL_GOLD, alpha))
	draw_rect(r.grow(-3.0), Color(COL_DARKER, alpha))
	draw_string(_font, Vector2(r.position.x, r.position.y + 25.0), Loc.t("成就解锁") + " · " + Loc.t(str(a[1])),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(COL_GOLD, alpha))
	draw_string(_font, Vector2(r.position.x, r.position.y + 46.0), Loc.t(str(a[2])), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Color(COL_TEXT, alpha))


## 大本营信息区第 4 页：成就，四个一行。
func _achievement_lines() -> Array:
	var lines := [Loc.t("成就") + " %d / %d" % [Achievements.count(), Achievements.LIST.size()]]
	for i in range(0, Achievements.LIST.size(), 4):
		var parts := PackedStringArray()
		for j in range(i, i + 4):
			if j < Achievements.LIST.size():
				var a: Array = Achievements.LIST[j]
				parts.append(("★ " if Achievements.has(a[0]) else "☆ ") + Loc.t(str(a[1])))
		lines.append("    ".join(parts))
	return lines


func _update_lap(delta: float) -> void:
	if state != State.PRACTICE or _car.path_id != Track.PATH_LOOP:
		_lap_t = -1.0
		_prev_loop_s = -1.0
		return
	if _lap_t >= 0.0:
		_lap_t += delta
	if _prev_loop_s >= 0.0 and _car.s < _prev_loop_s - 100.0:     # 里程绕回 0 = 过了环道起点
		if _lap_t >= 0.0:
			_last_lap = _lap_t
			var best := float(SaveData.data.get("best_lap", -1.0))
			_lap_record = best < 0.0 or _lap_t < best
			if _lap_record:
				SaveData.data["best_lap"] = _lap_t
				SaveData.save()
				if best >= 0.0:
					_celebrate(Loc.t("最快圈") + "  " + format_delta(_lap_t - best))
		_lap_t = 0.0
	_prev_loop_s = _car.s


## 练习时右上角：这一圈、上一圈、最快圈。
func _draw_laps() -> void:
	if state != State.PRACTICE or paused:
		return
	var right := GRID.x - 24.0
	var best := float(SaveData.data.get("best_lap", -1.0))
	var rows := [[Loc.t("本圈"), _lap_t, COL_TEXT], [Loc.t("上一圈"), _last_lap, COL_RECORD if _lap_record else COL_TEXT],
			[Loc.t("最快圈"), best, COL_RECORD]]
	var y := 34.0
	for r: Array in rows:
		_text_right(str(r[0]), right - 96.0, y, 14, COL_DIM)
		_text_right(format_time(float(r[1])) if float(r[1]) >= 0.0 else Loc.t("—"), right, y, 16, r[2])
		y += 22.0


## 擦护栏预警的屏幕边缘红光（第 3 轮 #2）：在滑出去的那一侧，从边缘向内渐隐，按 8 Hz 闪。
func _draw_rail_glow() -> void:
	if paused or not (state in [State.RUN, State.PRACTICE]):
		return
	var warn := WorldAudio.rail_warning(_car)
	if warn <= 0.0:
		return
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 8.0)
	var a := warn * pulse * 0.75
	var w := 120.0 * (0.4 + 0.6 * warn)
	var right := _car.lat > 0.0
	var x0 := GRID.x if right else 0.0
	var x1 := GRID.x - w if right else w
	var edge := Color(COL_RED, a)
	var clear := Color(COL_RED, 0.0)
	draw_polygon(PackedVector2Array([Vector2(x0, 0.0), Vector2(x1, 0.0), Vector2(x1, GRID.y), Vector2(x0, GRID.y)]),
			PackedColorArray([edge, clear, clear, edge]))


## 车速数字（设置里开，默认关；开发者 2026-11-19 第 2 轮 #6）：左上角。
func _draw_speedo() -> void:
	if not bool(SaveData.data.get("speedo", false)) or paused or not (state in [State.RUN, State.PRACTICE]):
		return
	var kmh := roundi(_car.v / CarSim.KMH)
	draw_string(_font, Vector2(24.0, 40.0), "%d" % kmh, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, COL_TEXT)
	draw_string(_font, Vector2(24.0 + 64.0, 40.0), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_DIM)


## 过弯评价：挡风玻璃下方正中，先放大弹出再淡出。完美 = 金黄，漂亮 = 暖白。
func _draw_corner_popup() -> void:
	var j: CornerJudge = _main.corner_judge
	if j == null or j.popup_t <= 0.0 or paused or not (state in [State.RUN, State.PRACTICE]):
		return
	var age := CornerJudge.POPUP_TIME - j.popup_t
	var alpha := clampf(j.popup_t / 0.4, 0.0, 1.0)
	var size := int(lerpf(34.0, 26.0, clampf(age / 0.15, 0.0, 1.0))) if j.popup_perfect else 22
	var col := COL_GOLD if j.popup_perfect else COL_TEXT
	_text_center(j.popup, 262.0 + 2.0, size, Color(COL_DARKER, alpha), Vector2(2.0, 0.0))
	_text_center(j.popup, 262.0, size, Color(col, alpha))


func _draw_menu(title: String, options: Array[String], selected: int, footer: String, extra: Array) -> void:
	draw_rect(Rect2(Vector2.ZERO, GRID), COL_SHADE)
	_text_center(Loc.t(title), 150.0, 34, COL_TEXT)
	var y := 215.0
	var gap := 34.0 if extra.is_empty() else 30.0
	for i in options.size():
		var on := i == selected
		_text_center(("▶  " if on else "    ") + Loc.t(options[i]), y, 20, COL_GOLD if on else COL_DIM)
		y += gap
	y += 14.0
	for line: String in extra:
		_text_center(line, y, 13, COL_DIM)
		y += 20.0
	_text_center(footer, 470.0, 12, COL_DIM)


## 大本营的成绩行（开发者 2026-11-19 第 1 轮 #9：加上奖牌和下一枚奖牌的目标时间）。
func _best_lines() -> Array:
	var lines := []
	var best_total := float(SaveData.data.get("best_total", -1.0))
	if best_total >= 0.0:
		lines.append(Loc.t("最好成绩") + "  " + format_time(best_total))
	var best_sections: Array = SaveData.data.get("best_sections", [-1.0, -1.0, -1.0])
	var medals: Array = SaveData.data.get("best_medals", [0, 0, 0])
	if _track == null:
		return lines
	var t := Tuning.d
	for i in 3:
		var best := float(best_sections[i]) if i < best_sections.size() else -1.0
		var tier := int(medals[i]) if i < medals.size() else 0
		var line := Loc.t(_track.section_names[i]) + "  " + (format_time(best) if best >= 0.0 else Loc.t("—"))
		if tier > 0:
			line += "  " + Loc.t(StickerDisplay.TIER_NAMES[tier])
		var th: PackedFloat32Array = [t.t53_forest_thresholds, t.t53_ice_thresholds, t.t53_city_thresholds][i]
		if tier < 4:
			var next := maxi(tier + 1, 2)            # 下一枚：铜(2) 银(3) 金(4)
			line += "    " + Loc.t("下一枚") + " " + Loc.t(StickerDisplay.TIER_NAMES[next]) + " ≤ " + format_time(th[4 - next])
		else:
			line += "    " + Loc.t("已拿满")
		lines.append(line)
	return lines


## 右上角：最近 3 个区段的成绩，新的在下面；刷新历史最好的时间用紫色。
func _draw_recent() -> void:
	var y := 34.0
	for item in recent:
		_text_right(Loc.t(str(item["name"])), GRID.x - 24.0 - 96.0, y, 16, COL_TEXT)
		_text_right(format_time(float(item["time"])), GRID.x - 24.0, y, 16, COL_RECORD if item["record"] else COL_TEXT)
		var diff := float(item.get("diff", NAN))
		if not is_nan(diff):
			_text_right(format_delta(diff), GRID.x - 24.0 - 96.0 - 64.0, y, 13, COL_FASTER if diff < 0.0 else COL_SLOWER)
		y += 22.0
	# 实时差值：本区段到这里比最好那趟快（绿、负）还是慢（红、正）
	var live: float = _main.ghost.delta if _main.ghost != null else NAN
	if state == State.RUN and not is_nan(live):
		_text_right(Loc.t("比最好"), GRID.x - 24.0 - 96.0, y + 6.0, 13, COL_DIM)
		_text_right(format_delta(live), GRID.x - 24.0, y + 8.0, 20, COL_FASTER if live < 0.0 else COL_SLOWER)


func _draw_results() -> void:
	draw_rect(Rect2(Vector2.ZERO, GRID), COL_SHADE)
	_text_center(Loc.t("完成") if single_section < 0 else Loc.t("区段完成"), 130.0, 34, COL_TEXT)
	var y := 195.0
	for i in section_times.size():
		var mine: float = section_times[i]
		var medal: String = Loc.t(StickerDisplay.TIER_NAMES[section_medals[i]]) if mine >= 0.0 else ""
		_text_pair(Loc.t(_track.section_names[i]), format_time(mine), y, 18, COL_RECORD if section_records[i] else COL_TEXT)
		if medal != "":
			_text_right(medal, GRID.x * 0.5 - 90.0, y, 14, COL_GOLD)
		y += 30.0
	y += 12.0
	if single_section >= 0:
		var c: Array = _main.corner_judge.counts
		_text_center(Loc.t("完美过弯") + " %d / %d    " % [c[0], c[2]] + Loc.t("撞车") + " %d    " % run_crashes
				+ Loc.t("最高") + " %d km/h" % roundi(run_top_kmh), y, 14, COL_DIM)
		_text_center(Loc.t("R 再跑一次"), 455.0, 12, COL_DIM)
	elif section_times.has(-1.0):
		_text_center(Loc.t("没有跑完整三个区段，不计总成绩"), y, 14, COL_DIM)
	else:
		_text_pair(Loc.t("总用时"), format_time(total_time()), y, 24, COL_RECORD if new_record else COL_TEXT)
		y += 34.0
		if not new_record:
			_text_pair(Loc.t("最好成绩"), format_time(float(SaveData.data.get("best_total", -1.0))), y, 14, COL_DIM, COL_DIM)
	_text_center(Loc.t("紫色 = 历史最好"), 440.0, 11, COL_RECORD)
	_text_center(Loc.t("回车：回大本营"), 470.0, 12, COL_DIM)


## 标题画面（9.2）。
func _draw_title() -> void:
	# 标题：朱红，(4, 4) 金黄硬投影；副标题暖白
	_text_center("STAR SPEED", 60.0 + 72.0 + 4.0, 72, COL_GOLD, Vector2(4.0, 0.0))
	_text_center("STAR SPEED", 60.0 + 72.0, 72, COL_RED)
	_text_center("星速", 140.0 + 48.0, 48, COL_TEXT)
	var list := title_buttons()
	for i in list.size():
		var b: Array = list[i]
		# 按钮多于 6 个时整体上移、间距收紧，保证最后一个不出画面
		var top := 232.0 if list.size() <= 6 else 206.0
		var gap := 50.0 if list.size() <= 6 else 46.0
		_draw_button(str(b[0]), Vector2(480.0, top + gap * i), i == _title_select, bool(b[1]))
	draw_string(_font, Vector2(24.0, 516.0 + 12.0), Loc.t("↑↓ 选择   回车 确定"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COL_DIM)


## 9.1 的按钮：320×44，4 像素边框，(4, 4) 更深蓝黑硬投影；选中时金黄填充，左侧外 16 像素一个朱红三角。
func _draw_button(text: String, center_top: Vector2, selected: bool, enabled: bool) -> void:
	var r := Rect2(Vector2(center_top.x - BUTTON_SIZE.x * 0.5, center_top.y), BUTTON_SIZE)
	var fill := COL_GOLD if (selected and enabled) else COL_DARK
	var border := COL_TEXT if enabled else COL_ROAD
	var text_col := COL_DARK if (selected and enabled) else (COL_TEXT if enabled else COL_DIM)
	if enabled:
		draw_rect(Rect2(r.position + Vector2(4.0, 4.0), r.size), COL_DARKER)
	draw_rect(r, border)
	draw_rect(r.grow(-4.0), fill)
	draw_string(_font, Vector2(r.position.x, r.position.y + 32.0), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, text_col)
	if selected and enabled:
		var tip := Vector2(r.position.x - 16.0, r.position.y + r.size.y * 0.5)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-14.0, -9.0), tip + Vector2(-14.0, 9.0)]), COL_RED)


## 居中的一行"名字  时间"：名字在中线左边右对齐，时间在中线右边左对齐，两者颜色分开。
func _text_pair(label: String, value: String, y: float, font_size: int, value_color: Color, label_color := COL_TEXT) -> void:
	var mid := GRID.x * 0.5
	draw_string(_font, Vector2(0.0, y), label, HORIZONTAL_ALIGNMENT_RIGHT, mid - 14.0, font_size, label_color)
	draw_string(_font, Vector2(mid + 14.0, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, value_color)


func _text_right(text: String, right_x: float, y: float, font_size: int, color: Color) -> void:
	draw_string(_font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_RIGHT, right_x, font_size, color)


func _text_center(text: String, y: float, font_size: int, color: Color, offset := Vector2.ZERO) -> void:
	draw_string(_font, Vector2(offset.x, y + offset.y), text, HORIZONTAL_ALIGNMENT_CENTER, GRID.x, font_size, color)


## 差值：+0.42 / −1.07（秒，两位小数）。
static func format_delta(seconds: float) -> String:
	return ("+" if seconds >= 0.0 else "−") + "%.2f" % absf(seconds)


static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return Loc.t("—")
	var whole := int(seconds)
	return "%d:%02d.%02d" % [whole / 60, whole % 60, int((seconds - whole) * 100.0)]
