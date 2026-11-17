extends Control
## 第 9.12 节调试信息（F3）。只有中文。

const FONT_PATH := "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf"
const COL_PANEL := Color("1b2233", 0.7)
const COL_TEXT := Color("f7ecd4")
const COL_FAIL := Color("ef4a2f")
const ZONE_NAMES: Array[String] = ["安静", "第一段", "第二段", "第三段", "挣扎"]
const ZONE_COLORS: Array[Color] = [Color("8a93a3"), Color("4fb8e6"), Color("ffc93c"), Color("ef4a2f"), Color("b5371f")]

var car: CarSim
var track: Track
var _font: Font


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as Font
	else:
		var sys := SystemFont.new()   # 字体文件缺失时用系统字体（第 12 节）
		sys.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif"])
		_font = sys


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if car == null or track == null:
		return
	var t := Tuning.d
	draw_rect(Rect2(8, 8, 320, 214), COL_PANEL)
	var kmh := car.v / CarSim.KMH
	_text(16, 14, 12, COL_TEXT, "车速 %d km/h   档位 %d   转速 %d" % [roundi(kmh), car.gear, roundi(car.rpm)])
	var section := "—"
	if car.path_id == Track.PATH_MAIN:
		section = track.section_names[track.section_index_at(car.s)]
	_text(16, 32, 12, COL_TEXT, "路径 %s   里程 %d m   区段 %s（%s）" % [
			track.path_name(car.path_id), roundi(car.s), section, track.segment_label_at(car.path_id, car.s)])
	_text(16, 50, 12, COL_TEXT, "过转计时 %.2f / %.2f   外滑 %.2f / %.1f m" % [
			car.overrev_timer, t.t11_overrev_limit, car.lat, t.slide_wall_m])
	_text(16, 68, 12, COL_TEXT, "星速 %s   画面方案 %s   帧率 %d" % [
			"是" if car.star_speed else "否", t.t48_fx_mode, roundi(Engine.get_frames_per_second())])
	var music := get_node_or_null("/root/Main/Audio/Music")
	if music != null:
		var m: Node = music.get_parent().get_parent()
		_text(560, 32, 12, COL_TEXT, "音乐节奏 %.0f%%（理想 %d km/h）  鼓 %.0f%% 主音 %.0f%%" % [
				music.pace * 100.0, roundi(m.pace_profile.ideal(car.path_id, car.s) / CarSim.KMH),
				music._gain[1] * 100.0, music._gain[2] * 100.0])

	var straight := absf(car.kappa) < CarSim.KAPPA_EPS
	var zone_name := "直道" if straight else ZONE_NAMES[car.tire_zone]
	_text(16, 96, 24, ZONE_COLORS[car.tire_zone], "轮胎：%s  %.1f%%" % [zone_name, car.ratio * 100.0])

	_draw_tire_bar(t)

	var here := "—" if straight else "%d km/h" % roundi(car.v_lim / CarSim.KMH)
	var ahead := "—"
	var arc := track.next_arc(car.path_id, car.s, car.exit_armed)
	if arc["found"]:
		ahead = "%d km/h" % roundi(sqrt(t.t20_grip_g * CarSim.G * float(arc["radius"])) / CarSim.KMH)
	_text(16, 168, 12, COL_TEXT, "本弯极限 %s   前方弯极限 %s" % [here, ahead])

	var f := car.last_fail
	if not f.is_empty():
		var msg := ""
		match int(f["kind"]):
			CarSim.Fail.DOWNSHIFT:
				msg = "降档过转（%d 档 → %d 档，%d 转）" % [f["gear"], f["to_gear"], roundi(f["rpm"])]
			CarSim.Fail.OVERREV:
				msg = "顶红线太久（%d 档，%d 转）" % [f["gear"], roundi(f["rpm"])]
			_:
				msg = "冲出赛道（%d 档，ratio %.1f%%）" % [f["gear"], float(f["ratio"]) * 100.0]
		_text(16, 186, 12, COL_FAIL, "上次失败：" + msg)


## 9.12 轮胎状态条：ratio 从 60% 到 110%，按 T-22 – T-25 的分界切成五块底色，白色竖线游标标出当前值。
func _draw_tire_bar(t: TuningData) -> void:
	var rect := Rect2(16, 132, 304, 28)
	var lo := 0.60
	var hi := 1.10
	var bounds: Array[float] = [lo, t.t22_zone1_start, t.t23_zone2_start, t.t24_zone3_start, 1.0, t.t25_struggle_max, hi]
	var cols: Array[Color] = [ZONE_COLORS[0], ZONE_COLORS[1], ZONE_COLORS[2], ZONE_COLORS[3], ZONE_COLORS[4], Color("1b2233")]
	for i in cols.size():
		var x0 := rect.position.x + rect.size.x * (bounds[i] - lo) / (hi - lo)
		var x1 := rect.position.x + rect.size.x * (bounds[i + 1] - lo) / (hi - lo)
		draw_rect(Rect2(x0, rect.position.y, x1 - x0, rect.size.y), cols[i])
		if i > 0:
			draw_string(_font, Vector2(x0 - 8, rect.position.y - 2), str(roundi(bounds[i] * 100.0)),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT)
	var cx := rect.position.x + rect.size.x * (clampf(car.ratio, lo, hi) - lo) / (hi - lo)
	draw_rect(Rect2(cx - 1, rect.position.y - 2, 2, rect.size.y + 4), Color.WHITE)


func _text(x: float, top: float, size: int, color: Color, text: String) -> void:
	draw_string(_font, Vector2(x, top + _font.get_ascent(size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
