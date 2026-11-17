class_name RunFlow
extends Control
## 一局的流程和它的界面（开发者 2026-11-15 定的）：
##   大本营：车停在车库里，选"主赛道 计时赛"或"练习环道"，回车出发。
##   计时赛：出库后在岔路口直行上主赛道，过森林起点线开始计时，三个区段连着跑；
##           撞车、爆缸都是爆炸后退到弯前复位，计时不停。过城市终点线后显示结算，回车回大本营。
##   练习：出库后在岔路口拐进环道随便绕圈，不计时；回车回大本营。
##   暂停：Esc。继续 / 回大本营 / 退出游戏。
## 这个节点在暂停时也照常运行（process_mode = ALWAYS），界面用 _draw 画在 960×540 的网格上。

enum State { BASE, PRACTICE, RUN, RESULTS }

const GRID := Vector2(960.0, 540.0)
const COL_TEXT := Color("f7ecd4")
const COL_GOLD := Color("ffc93c")
const COL_DIM := Color("8a93a3")
## 历史最好成绩的时间一律用紫色显示（右上角、结算），名字保持正常颜色
const COL_RECORD := Color("c77dff")
const RECENT_COUNT := 3
const COL_SHADE := Color(0.06, 0.08, 0.13, 0.72)
const BASE_OPTIONS: Array[String] = ["主赛道  计时赛", "练习环道"]
const PAUSE_OPTIONS: Array[String] = ["继续", "回大本营", "退出游戏"]

var state := State.BASE
var paused := false
var section_times: Array[float] = [-1.0, -1.0, -1.0]   ## 本局各区段用时，−1 = 没有
var new_record := false
var section_records: Array[bool] = [false, false, false]   ## 本局各区段是否刷新了历史最好
var section_medals: Array[int] = [0, 0, 0]                  ## 本局各区段评到的贴纸等级
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = GRID
	_font = ThemeDB.fallback_font


func setup(p_main: Node, p_car: CarSim, p_track: Track, p_hint: Label, p_cockpit: Cockpit) -> void:
	_cockpit = p_cockpit
	var medals: Array = SaveData.data.get("best_medals", [0, 0, 0])
	for i in 3:
		_cockpit.stickers.set_tier(i, int(medals[i]))
	_main = p_main
	_car = p_car
	_track = p_track
	_hint = p_hint


# ───────────────────────── 状态切换 ─────────────────────────

## 回大本营：车放回车库，停住，等玩家选。
func enter_base() -> void:
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
	var to_main := _select == 0
	_car.set_exit_armed(to_main)
	_car.mode = CarSim.Mode.DRIVE
	state = State.RUN if to_main else State.PRACTICE
	_update_hint()


## 调试用（F4 瞬移到区段起点）：直接进入计时赛状态；没跑过的区段没有成绩，结算时不记纪录。
func debug_enter_run() -> void:
	if state != State.RUN:
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
	var record := float(best_sections[index]) < 0.0 or seconds < float(best_sections[index])
	section_records[index] = record
	if record:
		best_sections[index] = seconds
		SaveData.data["best_sections"] = best_sections
		SaveData.save()
	# R-32 / R-33：按 T-53 评贴纸等级；高于存档里的最高等级就存档，挡风玻璃上的贴纸换掉并弹一下
	var tier := medal_for(index, seconds)
	section_medals[index] = tier
	var medals: Array = SaveData.data.get("best_medals", [0, 0, 0])
	if tier > int(medals[index]):
		medals[index] = tier
		SaveData.data["best_medals"] = medals
		SaveData.save()
		_cockpit.stickers.set_tier(index, tier, true)
	recent.append({"name": _track.section_names[index], "time": seconds, "record": record})
	while recent.size() > RECENT_COUNT:
		recent.pop_front()
	if index == section_times.size() - 1:
		_finish_run()


func _finish_run() -> void:
	state = State.RESULTS
	# 结算时车自己刹停在终点线后的尾段上
	_car.use_device_input = false
	_car.set_throttle(false)
	_car.brake = true
	new_record = false
	var complete := not section_times.has(-1.0)
	if complete:
		var total := total_time()
		var best_total := float(SaveData.data.get("best_total", -1.0))
		if best_total < 0.0 or total < best_total:
			SaveData.data["best_total"] = total
			new_record = true
	SaveData.save()
	_update_hint()


## T-53：用时 ≤ 金 / 银 / 铜门槛分别是 4 / 3 / 2，跑完但更慢是 1（塑料）。
static func medal_for(index: int, seconds: float) -> int:
	var t := Tuning.d
	var th: PackedFloat32Array = [t.t53_forest_thresholds, t.t53_ice_thresholds, t.t53_city_thresholds][index]
	for k in 3:
		if seconds <= th[k]:
			return 4 - k
	return 1


func total_time() -> float:
	var sum := 0.0
	for t in section_times:
		if t >= 0.0:
			sum += t
	return sum


func _update_hint() -> void:
	_hint.visible = state == State.PRACTICE
	_hint.text = "练习环道    回车：回大本营"


# ───────────────────────── 输入 ─────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not paused)
		get_viewport().set_input_as_handled()
		return
	if paused:
		if event.is_action_pressed("ui_up"):
			_pause_select = posmod(_pause_select - 1, PAUSE_OPTIONS.size())
		elif event.is_action_pressed("ui_down"):
			_pause_select = posmod(_pause_select + 1, PAUSE_OPTIONS.size())
		elif event.is_action_pressed("confirm"):
			_pause_choose()
		get_viewport().set_input_as_handled()
		return
	match state:
		State.BASE:
			if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
				_select = 1 - _select
			elif event.is_action_pressed("confirm"):
				_leave_base()
		State.PRACTICE, State.RESULTS:
			if event.is_action_pressed("confirm"):
				_main.call("return_to_base")


func _set_paused(on: bool) -> void:
	paused = on
	_pause_select = 0
	get_tree().paused = on
	AudioServer.set_bus_mute(0, on)       # 暂停时所有声音静音（循环声不会自己停）


func _pause_choose() -> void:
	match _pause_select:
		0:
			_set_paused(false)
		1:
			_set_paused(false)
			_main.call("return_to_base")
		2:
			get_tree().quit()


# ───────────────────────── 界面 ─────────────────────────

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if paused:
		_draw_menu("暂停", PAUSE_OPTIONS, _pause_select, "↑ ↓ 选择    回车 确定    Esc 继续", [])
	elif state == State.BASE:
		_draw_menu("大本营", BASE_OPTIONS, _select, "↑ ↓ 选择    回车 出发", _best_lines())
	elif state == State.RESULTS:
		_draw_results()
	if not paused and state != State.BASE:
		_draw_recent()


func _draw_menu(title: String, options: Array[String], selected: int, footer: String, extra: Array) -> void:
	draw_rect(Rect2(Vector2.ZERO, GRID), COL_SHADE)
	_text_center(title, 150.0, 34, COL_TEXT)
	var y := 215.0
	for i in options.size():
		var on := i == selected
		_text_center(("▶  " if on else "    ") + options[i], y, 20, COL_GOLD if on else COL_DIM)
		y += 34.0
	y += 14.0
	for line: String in extra:
		_text_center(line, y, 13, COL_DIM)
		y += 20.0
	_text_center(footer, 470.0, 12, COL_DIM)


func _best_lines() -> Array:
	var lines := []
	var best_total := float(SaveData.data.get("best_total", -1.0))
	if best_total >= 0.0:
		lines.append("最好成绩  %s" % format_time(best_total))
	var best_sections: Array = SaveData.data.get("best_sections", [])
	if best_sections.size() == 3 and _track != null:
		var parts := PackedStringArray()
		for i in 3:
			if float(best_sections[i]) >= 0.0:
				parts.append("%s %s" % [_track.section_names[i], format_time(float(best_sections[i]))])
		if not parts.is_empty():
			lines.append("区段最好  " + "    ".join(parts))
	return lines


## 右上角：最近 3 个区段的成绩，新的在下面；刷新历史最好的时间用紫色。
func _draw_recent() -> void:
	var y := 34.0
	for item in recent:
		_text_right(str(item["name"]), GRID.x - 24.0 - 96.0, y, 16, COL_TEXT)
		_text_right(format_time(float(item["time"])), GRID.x - 24.0, y, 16, COL_RECORD if item["record"] else COL_TEXT)
		y += 22.0


func _draw_results() -> void:
	draw_rect(Rect2(Vector2.ZERO, GRID), COL_SHADE)
	_text_center("完成", 130.0, 34, COL_TEXT)
	var y := 195.0
	for i in section_times.size():
		var mine: float = section_times[i]
		var medal: String = StickerDisplay.TIER_NAMES[section_medals[i]] if mine >= 0.0 else ""
		_text_pair(_track.section_names[i], format_time(mine), y, 18, COL_RECORD if section_records[i] else COL_TEXT)
		if medal != "":
			_text_right(medal, GRID.x * 0.5 - 90.0, y, 14, COL_GOLD)
		y += 30.0
	y += 12.0
	if section_times.has(-1.0):
		_text_center("没有跑完整三个区段，不计总成绩", y, 14, COL_DIM)
	else:
		_text_pair("总用时", format_time(total_time()), y, 24, COL_RECORD if new_record else COL_TEXT)
		y += 34.0
		if not new_record:
			_text_pair("最好成绩", format_time(float(SaveData.data.get("best_total", -1.0))), y, 14, COL_DIM, COL_DIM)
	_text_center("紫色 = 历史最好", 440.0, 11, COL_RECORD)
	_text_center("回车：回大本营", 470.0, 12, COL_DIM)


## 居中的一行"名字  时间"：名字在中线左边右对齐，时间在中线右边左对齐，两者颜色分开。
func _text_pair(label: String, value: String, y: float, font_size: int, value_color: Color, label_color := COL_TEXT) -> void:
	var mid := GRID.x * 0.5
	draw_string(_font, Vector2(0.0, y), label, HORIZONTAL_ALIGNMENT_RIGHT, mid - 14.0, font_size, label_color)
	draw_string(_font, Vector2(mid + 14.0, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, value_color)


func _text_right(text: String, right_x: float, y: float, font_size: int, color: Color) -> void:
	draw_string(_font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_RIGHT, right_x, font_size, color)


func _text_center(text: String, y: float, font_size: int, color: Color) -> void:
	draw_string(_font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_CENTER, GRID.x, font_size, color)


static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "—"
	var whole := int(seconds)
	return "%d:%02d.%02d" % [whole / 60, whole % 60, int((seconds - whole) * 100.0)]
