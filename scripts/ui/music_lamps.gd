class_name MusicLamps
extends Control
## 调试：分层音乐的三盏灯（F6 开关，开发者 2026-11-16）。只有中文。
##   灯：底轨 / 鼓 / 主音。亮度 = 这一层当前的音量；加入时灯外有一圈光晕。
##   正在防抖（低于退出线、还没退出）时，灯下面显示红色的倒计时条。
##   下面的条：车速 ÷ 理想车速，60%–110%。竖线是各层的加入线（长）和退出线（短），白色游标是当前值。

const FONT_PATH := "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf"
const COL_PANEL := Color("1b2233", 0.8)
const COL_TEXT := Color("f7ecd4")
const COL_OFF := Color("3a4150")
const COL_HOLD := Color("ef4a2f")
const NAMES: Array[String] = ["底轨", "鼓", "主音"]
const COLORS: Array[Color] = [Color("7bd65a"), Color("ffc93c"), Color("4fb8e6")]
const BAR_LO := 0.6
const BAR_HI := 1.1
const PANEL := Rect2(330, 8, 300, 114)

var music: Music
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as Font
	else:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif"])
		_font = sys


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if music == null:
		return
	var t := Tuning.d
	draw_rect(PANEL, COL_PANEL)
	var x0 := PANEL.position.x
	var y0 := PANEL.position.y
	_text(x0 + 8, y0 + 4, 12, COL_TEXT, "音乐分层（F6）   节奏 %d%%" % roundi(music.pace * 100.0))

	for i in 3:
		var c := Vector2(x0 + 60 + i * 90, y0 + 36)
		var gain: float = music._gain[i]
		if music._on[i]:
			draw_circle(c, 15.0, Color(COLORS[i], 0.3))
		draw_circle(c, 10.0, COL_OFF.lerp(COLORS[i], gain))
		draw_arc(c, 10.0, 0.0, TAU, 24, Color(COLORS[i], 0.8), 1.0)
		var label := NAMES[i] + (" 开" if music._on[i] else " 关")
		_text(c.x - 20, c.y + 13, 12, COLORS[i] if music._on[i] else COL_TEXT.darkened(0.4), label)
		# 防抖倒计时：低于退出线还没退的时候，条从满到空
		var below: float = music._below[i]
		if music._on[i] and below > 0.0:
			var left := 1.0 - below / maxf(t.music_off_hold_s, 0.01)
			draw_rect(Rect2(c.x - 18, c.y + 29, 36.0 * left, 3), COL_HOLD)

	var bar := Rect2(x0 + 12, y0 + 82, PANEL.size.x - 24, 6)
	draw_rect(bar, COL_OFF)
	var lines := [[t.music_drums_on, t.music_drums_off, COLORS[1]], [t.music_lead_on, t.music_lead_off, COLORS[2]]]
	for l in lines:
		var xa := _bar_x(bar, l[0])
		var xb := _bar_x(bar, l[1])
		draw_line(Vector2(xa, bar.position.y - 6), Vector2(xa, bar.end.y + 6), l[2], 2.0)
		draw_line(Vector2(xb, bar.position.y - 2), Vector2(xb, bar.end.y + 2), Color(l[2], 0.6), 1.0)
	var xp := _bar_x(bar, music.pace)
	draw_rect(Rect2(bar.position.x, bar.position.y + 1, xp - bar.position.x, 4), Color(COL_TEXT, 0.35))
	draw_line(Vector2(xp, bar.position.y - 4), Vector2(xp, bar.end.y + 4), Color.WHITE, 2.0)
	_text(x0 + 12, y0 + 94, 12, COLORS[1], "鼓 加入 %d%% 退出 %d%%" % [roundi(t.music_drums_on * 100.0), roundi(t.music_drums_off * 100.0)])
	_text(x0 + 156, y0 + 94, 12, COLORS[2], "主音 加入 %d%% 退出 %d%%" % [roundi(t.music_lead_on * 100.0), roundi(t.music_lead_off * 100.0)])


func _bar_x(bar: Rect2, v: float) -> float:
	return bar.position.x + bar.size.x * (clampf(v, BAR_LO, BAR_HI) - BAR_LO) / (BAR_HI - BAR_LO)


func _text(x: float, top: float, size: int, color: Color, text: String) -> void:
	draw_string(_font, Vector2(x, top + _font.get_ascent(size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
