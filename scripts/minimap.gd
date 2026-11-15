class_name Minimap
extends SubViewport
## 第 5.6 节全息小地图：每帧按前方赛道重建路带网格、摆放摄像机和箭头、设置全息着色器参数。
## 路带的形状、弯、坡、区段线、岔路口全部取自 track.gd 的同一张采样表。
## 场景里的长度都除以预看距离 D，所以摄像机固定不动：自车后方 0.15、上方 0.30，俯视 35°，垂直视野 50°。

const MAP_SIZE := Vector2i(220, 115)
const CAM_BACK := 0.15
const CAM_UP := 0.30
const CAM_PITCH_DEG := 35.0
const CAM_FOV := 50.0
const ROAD_WIDTH := 0.03            ## 路带宽 0.03 D
const EDGE_WIDTH := 0.0035          ## 边线宽（急弯加粗一倍）
const LINE_WIDTH := 0.006           ## 区段线沿路方向的宽度
const FILL_OPACITY := 0.25          ## 金黄填充 25% 不透明度（加色叠加时等于 25% 亮度）
const FADE_TAIL := 0.15             ## 最远的 15% 渐隐
const HEIGHT_SCALE := 3.0           ## 坡道按真实高度的 3 倍画
const LOOK_SMOOTH := 0.5
const TRUE_ROAD_WIDTH := 12.0
const ARROW_LENGTH := 0.07
const ARROW_WIDTH := 0.05
const ARROW_THICK := 0.012
## 按 5.6 的摄像机参数，自车所在的原点刚好落在画面下缘之外，所以箭头整体往前挪了这么多
const ARROW_FORWARD := 0.035
const STRUGGLE_BLINK_HZ := 10.0

const COL_GOLD := Color("ffc93c")
const COL_WHITE := Color("f7ecd4")
const COL_SKY := Color("4fb8e6")
const COL_RED := Color("ef4a2f")

var car: CarSim
var track: Track
var cockpit: Cockpit
var game_time := 0.0
var lookahead := 400.0

var _arrow_material: StandardMaterial3D

@onready var map_camera: Camera3D = $MapCamera
@onready var ribbon: MeshInstance3D = $RoadRibbon
@onready var arrow: MeshInstance3D = $CarArrow


func _ready() -> void:
	size = MAP_SIZE
	map_camera.fov = CAM_FOV
	map_camera.near = 0.01
	map_camera.far = 10.0
	map_camera.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-CAM_PITCH_DEG)), Vector3(0.0, CAM_UP, CAM_BACK))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	ribbon.material_override = m
	_arrow_material = m.duplicate() as StandardMaterial3D
	arrow.material_override = _arrow_material
	arrow.mesh = _build_arrow()
	lookahead = Tuning.d.t52_lookahead_min_m


func bind(p_car: CarSim, p_track: Track, p_cockpit: Cockpit) -> void:
	car = p_car
	track = p_track
	cockpit = p_cockpit


func _process(delta: float) -> void:
	if car == null:
		return
	game_time += delta
	var t := Tuning.d
	# T-52：预看距离 = clamp(v × 8 秒, 400 m, 1800 m)，0.5 秒时间常数平滑
	var want := clampf(car.v * t.t52_lookahead_seconds, t.t52_lookahead_min_m, t.t52_lookahead_max_m)
	lookahead += (want - lookahead) * (1.0 - exp(-delta / LOOK_SMOOTH))
	var d := lookahead

	var off := car.render_offset()
	var here := track.advance(car.path_id, car.s, off, car.exit_armed, car.from_access)
	var xf := track.transform_at(here[0], here[1])
	var fwd := -xf.basis.z
	var frame := Transform3D(Basis.looking_at(Vector3(fwd.x, 0.0, fwd.z).normalized(), Vector3.UP), xf.origin)
	var to_local := frame.affine_inverse()

	var route := track.route_ahead(here[0], here[1], d, car.exit_armed, car.from_access)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var main_pts := _localize(route["main"], to_local, d)
	_add_ribbon(verts, colors, main_pts, route["sharp"], float(route["step"]) / d, true)
	var branch: PackedVector3Array = route["branch"]
	if branch.size() >= 2:
		_add_ribbon(verts, colors, _localize(branch, to_local, d), PackedByteArray(), float(route["step"]) / d, false)
	for line_d: float in route["lines"]:
		_add_section_line(verts, colors, main_pts, line_d / d, float(route["step"]) / d)
	if verts.size() >= 3:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		ribbon.mesh = mesh

	# 自车箭头：过弯时随方向盘转角左右倾斜；挣扎时按外滑量向外偏移，并在朱红与晴空蓝之间闪烁
	var steer := cockpit.steer_angle_deg() if cockpit != null else 0.0
	var slide_x := car.lat / TRUE_ROAD_WIDTH * ROAD_WIDTH
	arrow.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(steer * 0.5)),
			Vector3(slide_x, ARROW_THICK, -ARROW_FORWARD))
	var red := car.tire_zone == CarSim.Zone.STRUGGLE and fposmod(game_time * STRUGGLE_BLINK_HZ, 1.0) < 0.5
	_arrow_material.albedo_color = COL_RED if red else COL_SKY


## 世界坐标 → 以自车为原点、车头朝 −Z、除以 D 的小地图坐标；高度放大 3 倍。
func _localize(points: PackedVector3Array, to_local: Transform3D, d: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		var q := to_local * p
		out.append(Vector3(q.x, q.y * HEIGHT_SCALE, q.z) / d)
	return out


func _side_at(pts: PackedVector3Array, i: int) -> Vector3:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length_squared() < 1e-12:
		return Vector3.RIGHT
	dir = dir.normalized()
	return Vector3(-dir.z, 0.0, dir.x)   # 右侧


func _add_ribbon(verts: PackedVector3Array, colors: PackedColorArray, pts: PackedVector3Array,
		sharp: PackedByteArray, step: float, fade_tail: bool) -> void:
	var n := pts.size()
	if n < 2:
		return
	var half := ROAD_WIDTH * 0.5
	var lift := Vector3(0.0, 0.0008, 0.0)
	for i in n - 1:
		var sa := _side_at(pts, i)
		var sb := _side_at(pts, i + 1)
		var fa := _fade(i * step, fade_tail, n * step)
		var fb := _fade((i + 1) * step, fade_tail, n * step)
		var a := pts[i]
		var b := pts[i + 1]
		_quad(verts, colors, a - sa * half, a + sa * half, b - sb * half, b + sb * half,
				COL_GOLD * FILL_OPACITY * fa, COL_GOLD * FILL_OPACITY * fb)
		var is_sharp := i < sharp.size() and sharp[i] == 1
		var w := EDGE_WIDTH * (2.0 if is_sharp else 1.0)
		for side: float in [-1.0, 1.0]:
			_quad(verts, colors,
					a + sa * side * (half - w) + lift, a + sa * side * half + lift,
					b + sb * side * (half - w) + lift, b + sb * side * half + lift,
					COL_GOLD * fa, COL_GOLD * fb)


func _fade(dist: float, fade_tail: bool, total: float) -> float:
	var limit := 1.0 if fade_tail else total
	return clampf((limit - dist) / (FADE_TAIL * limit), 0.0, 1.0)


func _add_section_line(verts: PackedVector3Array, colors: PackedColorArray, pts: PackedVector3Array,
		dist: float, step: float) -> void:
	var f := dist / step
	var i := int(f)
	if i < 0 or i >= pts.size() - 1:
		return
	var p := pts[i].lerp(pts[i + 1], f - i)
	var side := _side_at(pts, i)
	var along := Vector3(side.z, 0.0, -side.x) * LINE_WIDTH * 0.5
	var half := ROAD_WIDTH * 0.5
	var lift := Vector3(0.0, 0.0016, 0.0)
	var c := COL_WHITE * _fade(dist, true, 1.0)
	_quad(verts, colors, p - side * half - along + lift, p + side * half - along + lift,
			p - side * half + along + lift, p + side * half + along + lift, c, c)


func _quad(v: PackedVector3Array, c: PackedColorArray, a: Vector3, b: Vector3, d: Vector3, e: Vector3,
		col_near: Color, col_far: Color) -> void:
	col_near.a = 1.0
	col_far.a = 1.0
	v.append(a); v.append(b); v.append(e)
	v.append(a); v.append(e); v.append(d)
	c.append(col_near); c.append(col_near); c.append(col_far)
	c.append(col_near); c.append(col_far); c.append(col_far)


## 有厚度的扁箭头，尖端朝前（−Z）。顶面最亮，侧面暗一级，立体感来自厚度。
func _build_arrow() -> ArrayMesh:
	var hw := ARROW_WIDTH * 0.5
	var tip := Vector3(0.0, 0.0, -ARROW_LENGTH)
	var left := Vector3(-hw, 0.0, 0.0)
	var right := Vector3(hw, 0.0, 0.0)
	var notch := Vector3(0.0, 0.0, -ARROW_LENGTH * 0.3)
	var down := Vector3(0.0, -ARROW_THICK, 0.0)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var top := Color(1.0, 1.0, 1.0)
	var side := Color(0.55, 0.55, 0.55)
	for tri: Array in [[tip, left, notch], [tip, notch, right]]:
		for p: Vector3 in tri:
			verts.append(p)
			colors.append(top)
	var outline: Array[Vector3] = [tip, right, notch, left]
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		for p: Vector3 in [a, b, b + down, a, b + down, a + down]:
			verts.append(p)
			colors.append(side)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
