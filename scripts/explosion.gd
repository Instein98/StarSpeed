class_name Explosion
extends Control
## V-05 大爆炸（规格 8.5、7.3）：画在座舱画面之上、盖住全屏的 2D 演出，按 960×540 的像素网格绘制。
## 第一阶段 0.3 秒：金黄色充满画面，60 片朱红、金黄、暖白的三角形碎片从中心向外飞散并旋转；
## 第二阶段 1.2 秒：朱红色多边形火球从半个屏幕大翻滚膨胀到 1.5 个屏幕大，边缘是深蓝黑的烟团向上升。
## 只用色板里的纯色，所以不需要再压色板。

signal finished

const GRID := Vector2(960.0, 540.0)
const PHASE1 := 0.3
const PHASE2 := 1.2
const SHARD_COUNT := 60
const SMOKE_COUNT := 12

const COL_GOLD := Color("ffc93c")
const COL_RED := Color("ef4a2f")
const COL_RED_DARK := Color("b5371f")
const COL_WHITE := Color("f7ecd4")
const COL_DARK := Color("1b2233")

var _time := -1.0
var _shards: Array[Dictionary] = []
var _smoke: Array[Dictionary] = []
var _fire_sides := 10
var _fire_spin := 1.0


func _ready() -> void:
	visible = false


func play() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_shards.clear()
	var colors: Array[Color] = [COL_RED, COL_GOLD, COL_WHITE]
	for i in SHARD_COUNT:
		var angle := rng.randf_range(0.0, TAU)
		_shards.append({
			"dir": Vector2(cos(angle), sin(angle)),
			"speed": rng.randf_range(2200.0, 4200.0),   # 0.3 秒内飞出屏幕
			"size": rng.randf_range(20.0, 80.0),
			"rot": rng.randf_range(0.0, TAU),
			"spin": rng.randf_range(-14.0, 14.0),
			"color": colors[i % 3],
		})
	_smoke.clear()
	for i in SMOKE_COUNT:
		_smoke.append({
			"angle": TAU * i / SMOKE_COUNT + rng.randf_range(-0.2, 0.2),
			"size": rng.randf_range(60.0, 130.0),
			"rise": rng.randf_range(60.0, 160.0),
			"sides": rng.randi_range(5, 8),
			"rot": rng.randf_range(0.0, TAU),
		})
	_fire_sides = rng.randi_range(8, 12)
	_fire_spin = 1.0 if rng.randf() < 0.5 else -1.0
	_time = 0.0
	visible = true
	queue_redraw()


func stop() -> void:
	_time = -1.0
	visible = false


func _process(delta: float) -> void:
	if _time < 0.0:
		return
	_time += delta
	queue_redraw()
	if _time >= PHASE1 + PHASE2:
		_time = PHASE1 + PHASE2
		finished.emit()


func _draw() -> void:
	if _time < 0.0:
		return
	var center := GRID * 0.5
	draw_rect(Rect2(Vector2.ZERO, GRID), COL_GOLD)
	if _time < PHASE1:
		for sh in _shards:
			var pos: Vector2 = center + (sh["dir"] as Vector2) * float(sh["speed"]) * _time
			_polygon(pos, float(sh["size"]), 3, float(sh["rot"]) + float(sh["spin"]) * _time, sh["color"])
		return
	var u := clampf((_time - PHASE1) / PHASE2, 0.0, 1.0)
	# 火球：直径从半个屏幕到 1.5 个屏幕
	var radius := lerpf(GRID.x * 0.25, GRID.x * 0.75, u)
	_polygon(center, radius, _fire_sides, _fire_spin * u * 2.5, COL_RED)
	_polygon(center, radius * 0.6, _fire_sides, -_fire_spin * u * 3.5, COL_RED_DARK)
	_polygon(center, radius * 0.3, 8, _fire_spin * u * 5.0, COL_GOLD)
	for sm in _smoke:
		var a := float(sm["angle"])
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * radius + Vector2(0.0, -float(sm["rise"]) * u)
		_polygon(pos, float(sm["size"]) * (0.6 + u), int(sm["sides"]), float(sm["rot"]) + u, COL_DARK)


## 画一个正多边形；顶点对齐到像素网格。
func _polygon(center: Vector2, radius: float, sides: int, rotation_rad: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in sides:
		var a := rotation_rad + TAU * i / sides
		pts.append((center + Vector2(cos(a), sin(a)) * radius).round())
	draw_colored_polygon(pts, color)
