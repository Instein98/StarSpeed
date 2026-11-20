class_name MixPanel
extends Control
## 引擎混音面板（规格 9.11，开发者 2026-11-19 第 4 轮 #10）：F1 开关，调试工具，只有中文。
## 占画布左半边 (0, 0) – (480, 540)，深蓝黑 85%。打开时游戏不暂停，可以边开车边调。
## 规格写的是 8 层（加油 / 松油两套）、外星嗡鸣等，现在的引擎声已经简化成 4 层同源录音、音色只跟转速走，
## 所以面板只放现在真正在用的参数（engine_audio.gd / tire_audio.gd 读的 mix 键）。
## 操作：只用鼠标（键盘的 ↑ ↓ 在开车时是换挡）——点数值框左半边减、右半边加，滚轮上下滚动，点"保存"写入
## user://engine_mix.json（下次启动自动读取），"恢复默认"回到 data/engine_mix_default.json 的值（要再按保存才写盘）。

const COL_BG := Color("1b2233", 0.85)
const COL_TEXT := Color("f7ecd4")
const COL_DIM := Color("8a93a3")
const COL_GOLD := Color("ffc93c")
const ROW_H := 18.0
const TOP := 140.0
## [名字, 键, 下标(−1 = 不是数组), 最小, 最大, 步长]；layer_on_db 改的时候 layer_off_db 同步改
const ROWS: Array = [
	["2000 转层 音量 dB", "layer_on_db", 0, -24.0, 6.0, 0.5],
	["3500 转层 音量 dB", "layer_on_db", 1, -24.0, 6.0, 0.5],
	["5500 转层 音量 dB", "layer_on_db", 2, -24.0, 6.0, 0.5],
	["8000 转层 音量 dB", "layer_on_db", 3, -24.0, 6.0, 0.5],
	["层间交叠宽度", "overlap", -1, 0.5, 1.5, 0.05],
	["变调下限", "pitch_min", -1, 0.5, 1.0, 0.05],
	["变调上限", "pitch_max", -1, 1.0, 2.0, 0.05],
	["加油 / 松油切换 秒", "on_off_time", -1, 0.02, 0.3, 0.01],
	["松油时整体 dB", "off_set_db", -1, -24.0, 6.0, 0.5],
	["升档动力中断压低 dB", "shift_cut_db", -1, -24.0, 0.0, 0.5],
	["轮胎 刚碰到极限 dB", "tire_db", 0, -24.0, 6.0, 0.5],
	["轮胎 处于极限 dB", "tire_db", 1, -24.0, 6.0, 0.5],
	["轮胎 打滑 dB", "tire_db", 2, -24.0, 6.0, 0.5],
]
const INFO: Array[String] = [
	"引擎声 = 4 个转速层，都来自同一段真实录音。",
	"当前转速落在哪两层之间，就按距离混合这两层，",
	"并把每层的音高按 当前转速 ÷ 该层录音转速 变调。",
	"音色只跟转速走；松油时整体压低\"松油时整体\"。",
	"上面再叠：风声、轮胎声。下面的条是每层现在的音量。",
	"点数值框左半边减、右半边加；滚轮滚动。",
]

var engine: EngineAudio
var tires: TireAudio
var car: CarSim
var _font: Font
var _scroll := 0.0
var _saved_t := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_mix"):
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _saved_t >= 0.0:
		_saved_t += delta
		if _saved_t > 1.5:
			_saved_t = -1.0
	if visible:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var mb := event as InputEventMouseButton
	var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * mb.position
	if p.x > 480.0:
		return
	get_viewport().set_input_as_handled()
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll = maxf(0.0, _scroll - ROW_H * 2.0)
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll = minf(_max_scroll(), _scroll + ROW_H * 2.0)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var y := p.y + _scroll
	for i in ROWS.size():
		var ry := TOP + ROW_H * (i + 1)
		if y >= ry and y < ry + ROW_H and p.x >= 300.0 and p.x <= 460.0:
			_step(ROWS[i], -1.0 if p.x < 380.0 else 1.0)
			return
	var by := TOP + ROW_H * (ROWS.size() + 2)
	if y >= by and y < by + 22.0:
		if p.x >= 20.0 and p.x < 140.0:
			_save()
		elif p.x >= 160.0 and p.x < 300.0:
			_reset()


func _max_scroll() -> float:
	return maxf(0.0, TOP + ROW_H * (ROWS.size() + 4) - 540.0)


func _value(row: Array) -> float:
	var v: Variant = engine.mix.get(row[1]) if row[1] != "tire_db" else tires.mix.get(row[1])
	if int(row[2]) >= 0:
		return float((v as Array)[int(row[2])])
	return float(v)


func _step(row: Array, dir: float) -> void:
	var nv := clampf(snappedf(_value(row) + dir * float(row[5]), float(row[5])), float(row[3]), float(row[4]))
	var targets: Array = [tires.mix] if row[1] == "tire_db" else [engine.mix]
	for m: Dictionary in targets:
		if int(row[2]) >= 0:
			(m[row[1]] as Array)[int(row[2])] = nv
			if row[1] == "layer_on_db":
				(m["layer_off_db"] as Array)[int(row[2])] = nv
		else:
			m[row[1]] = nv
	engine.mix["tire_db"] = tires.mix["tire_db"]


func _save() -> void:
	var out := engine.mix.duplicate(true)
	out["tire_db"] = tires.mix["tire_db"]
	var f := FileAccess.open(EngineAudio.USER_MIX_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		_saved_t = 0.0


func _reset() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(EngineAudio.DEFAULT_MIX_PATH))
	if d is Dictionary:
		engine.mix = (d as Dictionary).duplicate(true)
		tires.mix = (d as Dictionary).duplicate(true)


func _draw() -> void:
	if engine == null:
		return
	draw_rect(Rect2(0, 0, 480, 540), COL_BG)
	var o := Vector2(0.0, -_scroll)
	_t(Vector2(16, 22) + o, "引擎混音面板（F1）", 16, COL_GOLD)
	for i in INFO.size():
		_t(Vector2(16, 42 + 14 * i) + o, INFO[i], 12, COL_TEXT)
	# 实时条：4 层当前音量 + 转速
	var meters: Array = engine._on
	for i in meters.size():
		var p := meters[i] as AudioStreamPlayer
		var lin := db_to_linear(p.volume_db) if p.playing else 0.0
		var x := 16.0 + i * 70.0
		draw_rect(Rect2(Vector2(x, 124) + o, Vector2(60, 8)), Color(COL_DIM, 0.4))
		draw_rect(Rect2(Vector2(x, 124) + o, Vector2(60.0 * clampf(lin, 0.0, 1.0), 8)), COL_GOLD)
	_t(Vector2(300, 132) + o, "转速 %d" % roundi(engine.audio_rpm), 12, COL_TEXT)
	for i in ROWS.size():
		var row: Array = ROWS[i]
		var y := TOP + ROW_H * (i + 1)
		_t(Vector2(16, y + 13) + o, str(row[0]), 12, COL_TEXT)
		draw_rect(Rect2(Vector2(300, y + 2) + o, Vector2(160, ROW_H - 4)), Color(COL_DIM, 0.3))
		var f := (_value(row) - float(row[3])) / (float(row[4]) - float(row[3]))
		draw_rect(Rect2(Vector2(300, y + 2) + o, Vector2(160.0 * f, ROW_H - 4)), Color(COL_GOLD, 0.5))
		_t(Vector2(300, y + 13) + o, "−", 12, COL_TEXT, 20.0)
		_t(Vector2(440, y + 13) + o, "+", 12, COL_TEXT, 20.0)
		_t(Vector2(330, y + 13) + o, ("%.2f" % _value(row)).rstrip("0").rstrip("."), 12, COL_TEXT, 100.0)
	var by := TOP + ROW_H * (ROWS.size() + 2)
	draw_rect(Rect2(Vector2(20, by) + o, Vector2(120, 22)), COL_GOLD, false, 2.0)
	_t(Vector2(20, by + 16) + o, "保存" if _saved_t < 0.0 else "已保存", 12, COL_GOLD, 120.0)
	draw_rect(Rect2(Vector2(160, by) + o, Vector2(140, 22)), COL_DIM, false, 2.0)
	_t(Vector2(160, by + 16) + o, "恢复默认", 12, COL_TEXT, 140.0)


func _t(pos: Vector2, text: String, size: int, col: Color, center_w := -1.0) -> void:
	var align := HORIZONTAL_ALIGNMENT_CENTER if center_w > 0.0 else HORIZONTAL_ALIGNMENT_LEFT
	draw_string(_font, pos, text, align, center_w, size, col)
