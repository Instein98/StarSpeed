class_name Scenery
extends Node3D
## 区段景物的摆放（规格 5.4、5.10、6.3–6.5、8.4）。替代之前路两侧的彩色测试方块。
## 所有模型来自 scenery_models.gd 的代码生成替身；摆放用固定随机种子，每次运行结果相同。
## 同一种模型按 800 m 见方的格子分成多个 MultiMesh，便于视锥剔除。
## 远景环和云跟着摄像机走，按当前区段环境切换。
##
## 和规格不一样的地方（见 QUESTIONS.md）：
## - 护栏放在所有圆弧的外侧（规格只放半径 ≤ 300 m 的），离中心线 slide_wall_m + 0.8 m（规格 6.5 m）：
##   打滑撞车发生在横向位移到 slide_wall_m 时，护栏放在那里，看上去就是滑出去撞上了护栏。
## - 箭头牌放在护栏外侧 1.5 m（规格 8 m，会挡在滑出去的路线上）。

const CHUNK := 800.0
const GRID_CELL := 64.0
const GRID_STEP := 4.0
const SECTION_BLEND := 150.0       ## 6.5.4：区段起点线前后 150 m 内密度降到 30%
const SECTION_BLEND_KEEP := 0.3
const BASE_RECT := Rect2(-20.0, -16.0, 40.0, 30.0)   ## 基地外观占的平面范围（规格坐标 x, y）
const BASE_NO_PLANT := 40.0        ## 5.10：基地外墙 40 m 之内不放植被
const JUNCTION_CLEAR := 9.0        ## 5.4：护栏、箭头牌离别的路不足 9 m 不放
const JUNCTION_SAME_ROAD := 100.0
const GUARDRAIL_SEG := 4.0
const GUARDRAIL_EXTEND := 30.0
const ARROW_RADIUS_MAX := 150.0
const ARROW_STEP := 15.0
const ARROW_OUTSIDE := 1.5
const VIADUCT_MIN_HEIGHT := 0.5
const FAR_RING_RADIUS := 3800.0
const CLOUD_TURN_DEG_PER_MIN := 1.0
const CLOUD_COUNTS: Array[int] = [12, 6, 8]
const SIGN_TEXT_PIXEL := 0.02

var track: Track
var material: Material
## 主赛道上横跨路面的物体（门、拱门、龙门架）的里程，掠过声 S-09 用
var overhead_s := PackedFloat64Array()
var _grid: Dictionary = {}
var _batches: Dictionary = {}       ## 模型键 → { 格子 → Array[Transform3D] }
var _meshes: Dictionary = {}
var _rings: Array[Node3D] = []      ## 每个区段环境一组：远景环 + 云
var _clouds: Array[Node3D] = []
var _gold_fx: Array[GoldFx] = [null, null, null]
var _neon: Node3D
var _buildings: Array = []        ## [变换, 变体] —— 金牌版城市的霓虹招牌用
var _env := 0


func build(p_track: Track, p_material: Material) -> void:
	track = p_track
	material = p_material
	_build_grid()
	_place_base()
	_place_guardrails()
	_place_forest_paths()
	_place_forest()
	_place_ice()
	_place_city()
	_flush()
	for i in 6:
		_build_sky_set(i)
	_build_neon()
	set_environment(0)


## 切到第 index 个区段环境的远景环和云（0 森林、1 冰原、2 城市）；gold = 金牌版（6.6）。
func set_environment(index: int, gold := false) -> void:
	_env = index + (3 if gold else 0)
	for i in _rings.size():
		_rings[i].visible = i == _env
	if _neon != null:
		_neon.visible = _env == 5


## 极光的方位以区段起点线处的车头方向为准（度，0 = 北）。
func set_gold_heading(section: int, heading_deg: float) -> void:
	if _gold_fx.size() > section and _gold_fx[section] != null:
		_gold_fx[section].heading_deg = heading_deg


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _rings.is_empty():
		return
	var p := cam.global_position
	var ring := _rings[_env]
	ring.global_position = Vector3(p.x, 0.0, p.z)
	if _env < _clouds.size():
		_clouds[_env].rotation.y += deg_to_rad(CLOUD_TURN_DEG_PER_MIN / 60.0) * delta


# ───────────────────────── 查询"附近有没有路" ─────────────────────────

func _build_grid() -> void:
	for p in 3:
		var s := 0.0
		var total := track.length(p)
		while true:
			var c := track.transform_at(p, s).origin
			var key := Vector2i(floori(c.x / GRID_CELL), floori(c.z / GRID_CELL))
			if not _grid.has(key):
				_grid[key] = []
			(_grid[key] as Array).append([Vector2(c.x, c.z), p, s])
			if s >= total:
				break
			s = minf(s + GRID_STEP, total)


## 平面点 q 离所有赛道中心线的最近距离（只查 GRID_CELL 范围内，更远的返回 GRID_CELL）。
## skip_path / skip_s：同一条路径上里程相差不到 skip_gap 的点不算（护栏、箭头牌的路口规则）。
func _road_distance(q: Vector2, skip_path := -1, skip_s := 0.0, skip_gap := 0.0) -> float:
	var base := Vector2i(floori(q.x / GRID_CELL), floori(q.y / GRID_CELL))
	var best := GRID_CELL
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := base + Vector2i(dx, dy)
			if not _grid.has(key):
				continue
			for e: Array in _grid[key]:
				if int(e[1]) == skip_path and absf(float(e[2]) - skip_s) < skip_gap:
					continue
				best = minf(best, (e[0] as Vector2).distance_to(q))
	return best


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# ───────────────────────── 批量实例 ─────────────────────────

func _add(key: String, xf: Transform3D) -> void:
	if not _batches.has(key):
		_batches[key] = {}
	var cell := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
	var by_cell: Dictionary = _batches[key]
	if not by_cell.has(cell):
		by_cell[cell] = []
	(by_cell[cell] as Array).append(xf)


func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh
	var parts := key.split(":")
	match parts[0]:
		"pine": m = SceneryModels.pine(int(parts[1]))
		"rock": m = SceneryModels.rock()
		"berg": m = SceneryModels.iceberg(int(parts[1]))
		"spikes": m = SceneryModels.ice_spikes()
		"arch": m = SceneryModels.ice_arch()
		"gate": m = SceneryModels.forest_gate()
		"bld": m = SceneryModels.building(int(parts[1]), SceneryModels.BUILDING_COLORS[int(parts[2])])
		"gantry": m = SceneryModels.gantry(parts[1] == "1")
		"pier": m = SceneryModels.pier()
		"rail": m = SceneryModels.guardrail(parts[1] == "1")
		"arrow": m = SceneryModels.arrow_sign(parts[1] == "1")
		"base": m = SceneryModels.base()
	_meshes[key] = m
	return m


func _flush() -> void:
	for key: String in _batches:
		var by_cell: Dictionary = _batches[key]
		for cell: Vector2i in by_cell:
			var list: Array = by_cell[cell]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _mesh(key)
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var node := MultiMeshInstance3D.new()
			node.name = "%s_%d_%d" % [key.replace(":", "_"), cell.x, cell.y]
			node.multimesh = mm
			node.material_override = material
			add_child(node)
	_batches.clear()


## 底面中心放在 pos、绕竖轴转 yaw、缩放 scale 的变换。
static func _xf(pos: Vector3, yaw: float, scale: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos)


## 横跨路面的物体（门、拱门、龙门架）：模型的横跨方向是 X，摆成和路垂直。
func _across(path: int, s: float) -> Transform3D:
	if path == Track.PATH_MAIN:
		overhead_s.append(s)
	var xf := track.transform_at(path, s)
	var f := -xf.basis.z
	var yaw := atan2(-f.x, -f.z)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(xf.origin.x, xf.origin.y if xf.origin.y > 0.0 else 0.0, xf.origin.z))


# ───────────────────────── 通用的散布 ─────────────────────────

## 沿 path 的 [s_from, s_to) 每 step 米、两侧各放一个：离中心线 d_min–d_max（随机），
## 离任何中心线不足 clear 的不放；pick(rng, pos, side, s) 返回 [键, 缩放] 或 []。
func _scatter(path: int, s_from: float, s_to: float, step: float, d_min: float, d_max: float,
		clear: float, rng: RandomNumberGenerator, pick: Callable, both_sides := true) -> void:
	var s := s_from + step * 0.5
	while s < s_to:
		var xf := track.transform_at(path, s)
		var r := track.right_at(path, s)
		var sides: Array = [-1.0, 1.0] if both_sides else [(-1.0 if rng.randf() < 0.5 else 1.0)]
		for side: float in sides:
			var d := rng.randf_range(d_min, d_max)
			var yaw := rng.randf() * TAU
			var keep_roll := rng.randf()
			var pos := xf.origin + r * side * d
			pos.y = 0.0
			if path == Track.PATH_MAIN and _near_section_line(s) and keep_roll > SECTION_BLEND_KEEP:
				continue
			if _road_distance(_flat(pos)) < clear:
				continue
			var choice: Array = pick.call(rng, pos, side, s)
			if choice.is_empty():
				continue
			var sc: float = choice[1]
			_add(choice[0], _xf(pos, yaw, Vector3.ONE * sc))
		s += step


func _near_section_line(s: float) -> bool:
	for i in range(1, track.section_names.size()):
		if absf(s - track.section_start[i]) < SECTION_BLEND:
			return true
	return false


## 一个区段（主赛道上）里最长的直道 [起点, 终点]。
func _longest_straight(section: int) -> Array[float]:
	var best: Array[float] = [0.0, 0.0]
	for seg in track.segments(Track.PATH_MAIN):
		if float(seg["kappa"]) != 0.0:
			continue
		var a: float = seg["start"]
		if track.section_index_at(a + 1.0) != section or a >= track.section_start[section + 1]:
			continue
		if float(seg["end"]) - a > best[1] - best[0]:
			best = [a, float(seg["end"])]
	return best


# ───────────────────────── 基地 ─────────────────────────

func _place_base() -> void:
	_add("base", Transform3D.IDENTITY)
	var label := Label3D.new()
	label.text = "STAR SPEED"
	label.font_size = 96
	label.pixel_size = SIGN_TEXT_PIXEL
	label.modulate = SceneryModels.COL_DARK
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.position = Vector3(-6.8, 3.5, 2.0)
	label.rotation = Vector3(0.0, PI * 0.5, 0.0)
	add_child(label)


func _near_base(pos: Vector3) -> bool:
	var q := Vector2(pos.x, -pos.z)
	return BASE_RECT.grow(BASE_NO_PLANT).has_point(q)


# ───────────────────────── 护栏、箭头牌（5.4） ─────────────────────────

func _place_guardrails() -> void:
	var dist := Tuning.d.slide_wall_m + 0.8
	var arrow_dist := dist + ARROW_OUTSIDE
	for p in 3:
		var total := track.length(p)
		for seg in track.segments(p):
			var kappa: float = seg["kappa"]
			if kappa == 0.0:
				continue
			var side := 1.0 if kappa > 0.0 else -1.0   # 左弯的外侧在右边
			var a := maxf(float(seg["start"]) - GUARDRAIL_EXTEND, 0.0)
			var b := minf(float(seg["end"]) + GUARDRAIL_EXTEND, total)
			var s := a
			var n := int(a / GUARDRAIL_SEG)
			while s < b:
				var mid := s + GUARDRAIL_SEG * 0.5
				var xf := track.transform_at(p, mid)
				var r := track.right_at(p, mid)
				var pos := xf.origin + r * side * dist
				if not _rail_blocked(p, mid, pos):
					var f := -xf.basis.z
					_add("rail:%d" % (n % 2), _xf(pos, atan2(-f.x, -f.z)))
				s += GUARDRAIL_SEG
				n += 1
			if 1.0 / absf(kappa) <= ARROW_RADIUS_MAX:
				s = float(seg["start"]) + ARROW_STEP * 0.5
				while s < float(seg["end"]):
					var xf := track.transform_at(p, s)
					var r := track.right_at(p, s)
					var pos := xf.origin + r * side * arrow_dist
					if not _rail_blocked(p, s, pos):
						var f := -xf.basis.z
						_add("arrow:%d" % (1 if kappa > 0.0 else 0), _xf(pos, atan2(-f.x, -f.z)))
					s += ARROW_STEP


## 路口例外（5.4）；城市高架上已经有护墙，也不放。
func _rail_blocked(p: int, s: float, pos: Vector3) -> bool:
	if p == Track.PATH_MAIN and track.section_index_at(s) == 2 and pos.y > 0.3:
		return true
	return _road_distance(_flat(pos), p, s, JUNCTION_SAME_ROAD) < JUNCTION_CLEAR


# ───────────────────────── 森林（6.4、6.5.1） ─────────────────────────

func _pine_pick(scale_min: float, scale_max: float) -> Callable:
	return func(rng: RandomNumberGenerator, pos: Vector3, _side: float, _s: float) -> Array:
		if _near_base(pos):
			return []
		return ["pine:%d" % rng.randi_range(0, 1), rng.randf_range(scale_min, scale_max)]


## 出库路和环道：两侧 16–80 m，每侧每 12 m 一棵；环道围出的内场不种树。
func _place_forest_paths() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1001
	var infield := PackedVector2Array()
	var s := 0.0
	while s < track.length(Track.PATH_LOOP):
		infield.append(_flat(track.transform_at(Track.PATH_LOOP, s).origin))
		s += 10.0
	var base_pick := _pine_pick(0.8, 1.3)
	var pick := func(r: RandomNumberGenerator, pos: Vector3, side: float, ss: float) -> Array:
		if Geometry2D.is_point_in_polygon(_flat(pos), infield):
			return []
		return base_pick.call(r, pos, side, ss)
	for p: int in [Track.PATH_ACCESS, Track.PATH_LOOP]:
		_scatter(p, 0.0, track.length(p), 12.0, 16.0, 80.0, 12.0, rng, pick)


func _place_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2001
	var a := 0.0
	var b := track.section_start[1]
	var tunnel := _longest_straight(0)
	var near := _pine_pick(0.8, 1.3)
	_scatter(Track.PATH_MAIN, a, b, 8.0, 14.0, 60.0, 12.0, rng, near)
	_scatter(Track.PATH_MAIN, a, b, 20.0, 60.0, 250.0, 12.0, rng, _pine_pick(1.5, 2.5))
	# 长直道：两侧 12–20 m 每 6 m 一棵大树，形成两堵树墙
	_scatter(Track.PATH_MAIN, tunnel[0], tunnel[1], 6.0, 12.0, 20.0, 12.0, rng, _pine_pick(1.5, 1.8))
	var rock_pick := func(r: RandomNumberGenerator, _p: Vector3, _sd: float, _s: float) -> Array: return ["rock", r.randf_range(0.8, 1.6)]
	_scatter(Track.PATH_MAIN, a, b, 60.0, 9.0, 14.0, 8.0, rng, rock_pick, false)
	# 森林门 A-24 立在森林起点线上
	_add("gate", _across(Track.PATH_MAIN, track.gate_s[0]))


# ───────────────────────── 冰原（6.5.2） ─────────────────────────

func _place_ice() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3001
	var a := track.section_start[1]
	var b := track.section_start[2]
	var berg_pick := func(r: RandomNumberGenerator, _p: Vector3, _sd: float, _s: float) -> Array: return ["berg:%d" % r.randi_range(0, 1), r.randf_range(1.0, 3.0)]
	var spike_pick := func(r: RandomNumberGenerator, _p: Vector3, _sd: float, _s: float) -> Array: return ["spikes", r.randf_range(0.8, 1.6)]
	_scatter(Track.PATH_MAIN, a, b, 120.0, 80.0, 400.0, 60.0, rng, berg_pick)
	_scatter(Track.PATH_MAIN, a, b, 12.0, 10.0, 40.0, 8.0, rng, spike_pick)
	# 冰拱门：冰原起点线一座；长直道上从起点后 200 m 开始每 300 m 一座，共 5 座
	_add("arch", _across(Track.PATH_MAIN, a))
	var lake := _longest_straight(1)
	for i in 5:
		var s := lake[0] + 200.0 + 300.0 * i
		if s < lake[1]:
			_add("arch", _across(Track.PATH_MAIN, s))


# ───────────────────────── 城市（6.5.3） ─────────────────────────

func _place_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4001
	var a := track.section_start[2]
	var b := track.length(Track.PATH_MAIN)
	var avenue := _longest_straight(2)
	var placed: Array = []   # [平面中心, 半径]
	var put_building := func(s: float, side: float, front: float, variant: int) -> void:
		var xf := track.transform_at(Track.PATH_MAIN, s)
		var r := track.right_at(Track.PATH_MAIN, s)
		var w: float = [18.0, 20.0, 22.0][variant] + 2.0
		var d: float = [18.0, 22.0, 24.0][variant] + 2.0
		var center := xf.origin + r * side * (front + d * 0.5)
		center.y = 0.0
		var c2 := _flat(center)
		var radius := 0.5 * Vector2(w, d).length()
		for q: Array in placed:
			if (q[0] as Vector2).distance_to(c2) < (float(q[1]) + radius) * 0.75:
				return
		# 临街面朝路；四个角和临街面中点离任何中心线都不小于 14 m
		var face := -r * side
		var yaw := atan2(-face.x, -face.z)
		var basis := Basis(Vector3.UP, yaw)
		for corner: Vector3 in [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(-w, 0, d), Vector3(w, 0, d), Vector3(0, 0, -d)]:
			if _road_distance(_flat(center + basis * (corner * 0.5))) < 14.0:
				return
		placed.append([c2, radius])
		_buildings.append([Transform3D(basis, center), variant, w - 2.0, d - 2.0])
		_add("bld:%d:%d" % [variant, rng.randi_range(0, SceneryModels.BUILDING_COLORS.size() - 1)], Transform3D(basis, center))
	# 大道两侧：14–18 m 每 24 m，只用 150 m 那一种，形成峡谷
	var s := avenue[0] + 12.0
	while s < avenue[1]:
		for side: float in [-1.0, 1.0]:
			put_building.call(s, side, rng.randf_range(14.0, 18.0), 2)
		s += 24.0
	s = a + 14.0
	while s < b:
		if s < avenue[0] or s > avenue[1]:
			for side: float in [-1.0, 1.0]:
				if _near_section_line(s) and rng.randf() > SECTION_BLEND_KEEP:
					continue
				put_building.call(s, side, rng.randf_range(16.0, 30.0), rng.randi_range(0, 2))
		s += 28.0
	# 龙门架：城市起点线、终点线（朱红，带 FINISH 字样）、大道上每 300 m 一座共 3 座
	_add("gantry:0", _across(Track.PATH_MAIN, a))
	for i in 3:
		var gs := avenue[0] + 300.0 * (i + 1)
		if gs < avenue[1]:
			_add("gantry:0", _across(Track.PATH_MAIN, gs))
	var finish := _across(Track.PATH_MAIN, track.gate_s[3])
	_add("gantry:1", finish)
	var label := Label3D.new()
	label.text = "FINISH"
	label.font_size = 96
	label.pixel_size = 0.03
	label.modulate = SceneryModels.COL_GOLD
	label.outline_size = 0
	label.shaded = false
	label.transform = finish * Transform3D(Basis.IDENTITY, Vector3(0.0, 7.9, 0.75))
	add_child(label)
	# 高架桥墩：路面抬高处每 30 m 一个，高度 = 路面高度
	s = a
	while s < b:
		var xf := track.transform_at(Track.PATH_MAIN, s)
		if xf.origin.y > VIADUCT_MIN_HEIGHT:
			var f := -xf.basis.z
			_add("pier", _xf(Vector3(xf.origin.x, -0.2, xf.origin.z), atan2(-f.x, -f.z), Vector3(1.0, xf.origin.y + 0.2, 1.0)))
		s += 30.0


# ───────────────────────── 远景环（A-61）和云（A-60） ─────────────────────────

func _build_sky_set(index: int) -> void:
	var root := Node3D.new()
	root.name = "Sky_%d" % index
	add_child(root)
	_rings.append(root)
	var ring := MeshInstance3D.new()
	ring.mesh = _far_ring(index % 3, index >= 3)
	ring.material_override = material
	ring.extra_cull_margin = 10000.0
	root.add_child(ring)
	var clouds := Node3D.new()
	root.add_child(clouds)
	_clouds.append(clouds)
	if index >= 3:
		# 金牌版：夜里没有云，换成氛围物（城市的霓虹招牌挂在楼上，另外建）
		var fx := GoldFx.new()
		fx.kind = ["meteor", "aurora", ""][index - 3]
		fx.material_override = material
		root.add_child(fx)
		_gold_fx[index - 3] = fx
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _clouds_mesh(index)
	mi.material_override = material
	mi.extra_cull_margin = 10000.0
	clouds.add_child(mi)


## 单层环形剪影，半径 3800 m，轮廓高度 150–500 m。0 圆缓的蓝色山脊，1 尖锐的白色雪峰，2 城市天际线。
func _far_ring(index: int, night := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5001 + index
	var k := MeshKit.new()
	var n := 180
	var heights := PackedFloat32Array()
	match index:
		0:
			var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
			for i in n:
				var a := TAU * i / n
				var h := 0.5 + 0.25 * sin(a * 3.0 + ph[0]) + 0.15 * sin(a * 7.0 + ph[1]) + 0.1 * sin(a * 13.0 + ph[2])
				heights.append(lerpf(150.0, 500.0, clampf(h, 0.0, 1.0)))
		1:
			for i in n:
				heights.append(rng.randf_range(150.0, 500.0) if i % 2 == 0 else rng.randf_range(120.0, 220.0))
		2:
			var i := 0
			while i < n:
				var w := rng.randi_range(1, 3)
				var h := rng.randf_range(150.0, 500.0)
				for j in w:
					if i < n:
						heights.append(h)
						i += 1
	# 自发光：远景环是一整圈朝内的竖面，按两级明暗会有半圈落到暗面，远山的蓝色压色板后会变成暗绿
	var col: Color = [SceneryModels.COL_MOUNTAIN, SceneryModels.COL_SNOW_SHADE, SceneryModels.COL_MOUNTAIN][index]
	if night:
		col = [Color("3a5a80"), Color("3a5a80"), Color("2b3550")][index]
	col.a = 0.0
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0), 0.0, sin(a0)) * FAR_RING_RADIUS
		var p1 := Vector3(cos(a1), 0.0, sin(a1)) * FAR_RING_RADIUS
		var bottom := Vector3(0.0, -60.0, 0.0)
		if index == 2:
			# 天际线：每格是平顶矩形
			k.quad(p0 + bottom, p1 + bottom, p1 + Vector3(0, heights[i], 0), p0 + Vector3(0, heights[i], 0), col)
		else:
			var h1 := heights[(i + 1) % n]
			k.quad(p0 + bottom, p1 + bottom, p1 + Vector3(0, h1, 0), p0 + Vector3(0, heights[i], 0), col)
	return k.build()


## 云：天穹上（半径 3800 m 往里一点）仰角 12°–40°、方位随机的白色扁平多边形块，底边平直，宽 300–800 m。
func _clouds_mesh(index: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6001 + index
	var k := MeshKit.new()
	var col := Color(1.0, 1.0, 1.0, 0.0)   # 自发光纯白
	var r := FAR_RING_RADIUS - 200.0
	for c in CLOUD_COUNTS[index]:
		var az := rng.randf() * TAU
		var el := deg_to_rad(rng.randf_range(12.0, 40.0))
		var center := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)) * r
		var right := Vector3(-sin(az), 0.0, cos(az))
		var w := rng.randf_range(300.0, 800.0)
		var h := w * rng.randf_range(0.15, 0.25)
		var bumps := rng.randi_range(3, 5)
		var pts: Array[Vector3] = []
		for i in bumps * 2 + 1:
			var u := float(i) / (bumps * 2)
			var top := h * (0.55 + 0.45 * (1.0 if i % 2 == 1 else rng.randf_range(0.3, 0.6))) * sin(PI * u * 0.9 + 0.15)
			pts.append(center + right * (u - 0.5) * w + Vector3.UP * top)
		for i in pts.size() - 1:
			var b0 := center + right * ((float(i) / (pts.size() - 1)) - 0.5) * w
			var b1 := center + right * ((float(i + 1) / (pts.size() - 1)) - 0.5) * w
			k.quad(b0, b1, pts[i + 1], pts[i], col)
	return k.build()


# ───────────────────────── 金牌版城市的霓虹招牌（A-62c） ─────────────────────────

## 每栋楼的临街面挂 1–2 块：竖条挂在楼高的 30%–60% 处，横条挂在离地 12 m 处，左右位置随机；粉或青，自发光。
func _build_neon() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6603
	var k := MeshKit.new()
	var pink := Color(1.0, 0.31, 0.69, 0.0)
	var cyan := Color(0.212, 0.878, 0.878, 0.0)
	for b: Array in _buildings:
		var xf: Transform3D = b[0]
		var h: float = SceneryModels.BUILDING_HEIGHTS[int(b[1])]
		var w: float = b[2]
		var d: float = b[3]
		for n in rng.randi_range(1, 2):
			var col := pink if rng.randf() < 0.5 else cyan
			var x := rng.randf_range(-w * 0.35, w * 0.35)
			var center: Vector3
			var size: Vector3
			if rng.randf() < 0.5:
				size = Vector3(1.6, h * 0.3 * rng.randf_range(0.6, 1.0), 0.4)
				center = Vector3(x, h * rng.randf_range(0.3, 0.6), -d * 0.5 - 0.4)
			else:
				size = Vector3(rng.randf_range(6.0, 10.0), 2.0, 0.4)
				center = Vector3(x, 12.0, -d * 0.5 - 0.4)
			k.box(xf * center, size, col, xf.basis.get_euler().y)
	_neon = MeshInstance3D.new()
	_neon.name = "Neon"
	_neon.mesh = k.build()
	_neon.material_override = material
	_neon.visible = false
	add_child(_neon)