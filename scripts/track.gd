class_name Track
extends Node3D
## 赛道：按 TrackData 生成唯一的一张采样表；路面网格、小地图、CarSim 都从这里读（规格 5.4、6.2、11.8）。
## path_id：0 = 出库路，1 = 环道，2 = 主赛道。
## 凡是要看"前方"的查询都带 exit_armed（过岔路口走哪条路）；出库路末端自动接环道。
## 看"后方"的查询带 from_access：车是从出库路并入环道的（回看取出库路），还是绕圈过来的（回看取 L6）。

const PATH_ACCESS := 0
const PATH_LOOP := 1
const PATH_MAIN := 2

const FORK_SEG := 0            ## 环道 L1（下标 0）的终点是岔路口（6.4）
const G := 9.8

# —— 路面外观（5.4、6.3）——
const ROAD_HALF_WIDTH := 6.0
const EDGE_LINE_INNER := 5.2   ## 边线 0.3 m 宽，距路缘 0.5 m
const EDGE_LINE_OUTER := 5.5
const CENTER_LINE_HALF := 0.125
const DASH_LENGTH := 6
const DASH_PERIOD := 18        ## 6 m 实线 + 12 m 间隔
## 区段的起终点线（地面上的黑白棋盘格带）。森林的起点线不放在岔路口，往后挪到主赛道 150 m 处，
## 这样它只在主赛道上、离车库也远一些；其余三条在区段交界处。
const START_LINE_S := 150.0
const CHECKER_ROWS := 6
const CHECKER_SQUARE := 1.0
const COL_CHECKER_DARK := Color("1b2233")
const LINE_LIFT := 0.005       ## 车道线抬高一点，避免与重叠的路面共面闪烁
const JUNCTION_CLEAR := 9.0    ## 距主直道中心线 9 m 之内，另一条路不画车道线
const MAIN_STRAIGHT_Y_MAX := 1000.0  ## 主直道 P1 + L1 + F1：x = 0，y 从 0 到 1000
const GARAGE_DOOR_Y := 14.0
const GARAGE_DOOR_HALF := 4.0
const GARAGE_TAPER := 10.0
const PARAPET_HEIGHT := 0.8
const PARAPET_THICK := 0.3
const GROUND_HALF_WIDTH := 600.0
const GROUND_STEP := 20
const GROUND_OVERLAP := 150.0
const SECTION_GROUND_Y: Array[float] = [-0.05, -0.10, -0.15]
const LAKE_Y := -0.03
const LAKE_SEG_LABEL := "I18"

const COL_ROAD := Color("4a5262")
const COL_ROAD_DARK := Color("363d4b")
const COL_EDGE := Color("ffc93c")
const COL_CENTER := Color("f7ecd4")
const COL_PARAPET := Color("8a93a3")
## 各区段白天版地面色（6.5）；阶段 2 之后由环境配置接管。
const COL_GROUND: Array[Color] = [Color("58b97a"), Color("f4fbff"), Color("3a4150")]
const COL_LAKE := Color("a5dcf2")

@export var access_data: TrackData
@export var loop_data: TrackData
@export var main_data: TrackData


class PathTable:
	extends RefCounted
	var data: TrackData
	var total := 0.0
	var seg_count := 0
	var seg_start := PackedFloat64Array()   # 每段起点里程，末尾多一项 = total
	var seg_kappa := PackedFloat64Array()   # 原始曲率，左正右负
	var seg_grade := PackedFloat64Array()   # 原始坡度（小数）
	var seg_x := PackedFloat64Array()
	var seg_y := PackedFloat64Array()
	var seg_yaw := PackedFloat64Array()
	var cum_kappa := PackedFloat64Array()   # ∫κ ds 到每段起点，末尾多一项
	var cum_grade := PackedFloat64Array()
	var pos := PackedVector3Array()         # 每 1 m 一个采样（最后一个在 total 处），Godot 坐标
	var yaw := PackedFloat64Array()
	var sample_s := PackedFloat64Array()


var _pt: Array[PathTable] = []
var fork_s := 0.0
var gate_s := PackedFloat64Array()          ## 区段起终点线的里程：森林起点、森林/冰原、冰原/城市、城市终点
var section_start := PackedFloat64Array()   ## 主赛道区段线里程，共 区段数 + 1 项
var section_names := PackedStringArray()

@onready var road_mesh: MeshInstance3D = $RoadMesh
@onready var ground_mesh: MeshInstance3D = $GroundMesh


func _ready() -> void:
	build()


func build() -> void:
	_pt = [_build_path(access_data), _build_path(loop_data), _build_path(main_data)]
	fork_s = _pt[PATH_LOOP].seg_start[FORK_SEG + 1]
	section_names = main_data.section_names
	section_start = PackedFloat64Array([0.0])
	var seg := 0
	for c in main_data.section_seg_counts:
		seg += c
		section_start.append(_pt[PATH_MAIN].seg_start[seg])
	gate_s = PackedFloat64Array([START_LINE_S, section_start[1], section_start[2], section_start[3]])
	if is_inside_tree() and road_mesh != null:
		_build_meshes()


# ───────────────────────── 查询接口 ─────────────────────────

func length(path_id: int) -> float:
	return _pt[path_id].total


func path_name(path_id: int) -> String:
	return _pt[path_id].data.path_name


## 主赛道里程所在的区段下标（终点线之后的尾段算最后一个区段）。
func section_index_at(s: float) -> int:
	for i in range(section_names.size() - 1, -1, -1):
		if s >= section_start[i]:
			return i
	return 0


## 所在分段的规格编号（如 "F15"）。
func segment_label_at(path_id: int, s: float) -> String:
	var pt := _pt[path_id]
	return pt.data.seg_label[_seg_index(pt, s)]


## 从 (path_id, s) 沿路线前进 d 米（d 可为负）之后所在的 [path_id, s]。
func advance(path_id: int, s: float, d: float, exit_armed := false, from_access := false) -> Array:
	var p := path_id
	var cur := s
	if d >= 0.0:
		var rem := d
		while true:
			var bound := 0.0
			var np := PATH_LOOP
			match p:
				PATH_ACCESS:
					bound = _pt[PATH_ACCESS].total
				PATH_LOOP:
					if exit_armed and cur < fork_s:
						bound = fork_s
						np = PATH_MAIN
					else:
						bound = _pt[PATH_LOOP].total
				_:
					return [PATH_MAIN, minf(cur + rem, _pt[PATH_MAIN].total)]
			if cur + rem < bound:
				return [p, cur + rem]
			rem -= bound - cur
			p = np
			cur = 0.0
	else:
		var rem := -d
		while true:
			if rem <= cur:
				return [p, cur - rem]
			rem -= cur
			match p:
				PATH_ACCESS:
					return [PATH_ACCESS, 0.0]
				PATH_LOOP:
					if from_access:
						p = PATH_ACCESS
						cur = _pt[PATH_ACCESS].total
					else:
						cur = _pt[PATH_LOOP].total
				_:
					p = PATH_LOOP
					cur = fork_s
	return [p, cur]


## 中心线上的位置与朝向（含坡度）；s 限制在该路径范围内。
func transform_at(path_id: int, s: float) -> Transform3D:
	var pt := _pt[path_id]
	s = clampf(s, 0.0, pt.total)
	var i := mini(int(s), pt.pos.size() - 2)
	var s0 := pt.sample_s[i]
	var ds := pt.sample_s[i + 1] - s0
	var f := 0.0 if ds <= 0.0 else clampf((s - s0) / ds, 0.0, 1.0)
	var a := pt.pos[i]
	var b := pt.pos[i + 1]
	var yaw := lerpf(pt.yaw[i], pt.yaw[i + 1], f)
	var slope := 0.0 if ds <= 0.0 else (b.y - a.y) / ds
	var fwd := Vector3(sin(yaw), slope, -cos(yaw)).normalized()
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), a.lerp(b, f))


## 该处指向车右侧的水平单位向量。
func right_at(path_id: int, s: float) -> Vector3:
	var pt := _pt[path_id]
	s = clampf(s, 0.0, pt.total)
	var i := mini(int(s), pt.pos.size() - 2)
	var ds := pt.sample_s[i + 1] - pt.sample_s[i]
	var f := 0.0 if ds <= 0.0 else clampf((s - pt.sample_s[i]) / ds, 0.0, 1.0)
	var yaw := lerpf(pt.yaw[i], pt.yaw[i + 1], f)
	return Vector3(cos(yaw), 0.0, sin(yaw))


## R-11：已平滑的曲率（左正右负）。
func curvature_at(path_id: int, s: float, exit_armed := false, from_access := false) -> float:
	return _route_average(path_id, s, exit_armed, from_access, true)


## R-11：已平滑的坡度（小数，上坡为正）。
func grade_at(path_id: int, s: float, exit_armed := false, from_access := false) -> float:
	return _route_average(path_id, s, exit_armed, from_access, false)


## 前方最近的圆弧（车正在圆弧上时就是这段圆弧，此时 entry_dist 为负）。
## 返回 found、entry_dist、apex_dist、exit_dist、length、radius、dir（+1 左 / −1 右）、
## path_id、s_entry、apex（弯心点：圆弧中点处的路面中心）、exit（出口点）。
func next_arc(path_id: int, s: float, exit_armed := false) -> Dictionary:
	var p := path_id
	var pt := _pt[p]
	var i := _seg_index(pt, s)
	var dist := pt.seg_start[i] - s
	for _n in 200:
		var seg_len := pt.seg_start[i + 1] - pt.seg_start[i]
		if pt.seg_kappa[i] != 0.0:
			var s_entry := pt.seg_start[i]
			return {
				"found": true,
				"entry_dist": dist,
				"apex_dist": dist + seg_len * 0.5,
				"exit_dist": dist + seg_len,
				"length": seg_len,
				"radius": 1.0 / absf(pt.seg_kappa[i]),
				"dir": 1 if pt.seg_kappa[i] > 0.0 else -1,
				"path_id": p,
				"s_entry": s_entry,
				"apex": transform_at(p, s_entry + seg_len * 0.5).origin,
				"exit": transform_at(p, s_entry + seg_len).origin,
			}
		dist += seg_len
		if p == PATH_LOOP and exit_armed and i == FORK_SEG:
			p = PATH_MAIN
			i = 0
		else:
			i += 1
			if i >= pt.seg_count:
				if p == PATH_MAIN:
					break
				p = PATH_LOOP
				i = 0
		pt = _pt[p]
	return {"found": false}


# ───────────────────────── 采样表 ─────────────────────────

func _build_path(data: TrackData) -> PathTable:
	var pt := PathTable.new()
	pt.data = data
	pt.seg_count = data.seg_type.size()
	var x := float(data.start.x)
	var y := float(data.start.y)
	var yaw := deg_to_rad(data.heading_deg)
	var s := 0.0
	var ck := 0.0
	var cg := 0.0
	for i in pt.seg_count:
		var seg_len := 0.0
		var kappa := 0.0
		if data.seg_type[i] == 0:
			seg_len = data.seg_length[i]
		else:
			var r := float(data.seg_radius[i])
			seg_len = r * deg_to_rad(data.seg_angle_deg[i])
			kappa = (1.0 if data.seg_type[i] == 1 else -1.0) / r
		var grade := data.seg_grade_pct[i] / 100.0
		pt.seg_start.append(s)
		pt.seg_kappa.append(kappa)
		pt.seg_grade.append(grade)
		pt.seg_x.append(x)
		pt.seg_y.append(y)
		pt.seg_yaw.append(yaw)
		pt.cum_kappa.append(ck)
		pt.cum_grade.append(cg)
		var e := _eval_seg(x, y, yaw, kappa, seg_len)
		x = e[0]
		y = e[1]
		yaw = e[2]
		s += seg_len
		ck += kappa * seg_len
		cg += grade * seg_len
	pt.seg_start.append(s)
	pt.cum_kappa.append(ck)
	pt.cum_grade.append(cg)
	pt.total = s

	# 每 1 m 一个采样；高度 = 平滑后的坡度沿里程积分（6.2）
	var w: float = Tuning.d.t21_smooth_window_m
	var count := int(ceil(pt.total)) + 1
	var h := 0.0
	var prev_s := 0.0
	for n in count:
		var ss := minf(float(n), pt.total)
		if n > 0:
			var mid := (prev_s + ss) * 0.5
			var g := _integral(pt, mid - w, mid + w, false) / (2.0 * w)
			h += g * (ss - prev_s)
		var i := _seg_index(pt, ss)
		var e := _eval_seg(pt.seg_x[i], pt.seg_y[i], pt.seg_yaw[i], pt.seg_kappa[i], ss - pt.seg_start[i])
		pt.pos.append(Vector3(e[0], h, -e[1]))
		pt.yaw.append(e[2])
		pt.sample_s.append(ss)
		prev_s = ss
	return pt


## 从 (x, y, yaw) 出发沿一段（曲率 kappa）前进 u 米后的 [x, y, yaw]。
func _eval_seg(x: float, y: float, yaw: float, kappa: float, u: float) -> Array[float]:
	if kappa == 0.0:
		return [x + sin(yaw) * u, y + cos(yaw) * u, yaw]
	var sg := signf(kappa)
	var r := 1.0 / absf(kappa)
	# 左侧单位向量 = (−cos yaw, sin yaw)；左弧时圆心在左侧
	var cx := x + sg * r * -cos(yaw)
	var cy := y + sg * r * sin(yaw)
	var yaw2 := yaw - sg * u / r
	return [cx - sg * r * -cos(yaw2), cy - sg * r * sin(yaw2), yaw2]


func _seg_index(pt: PathTable, s: float) -> int:
	return clampi(pt.seg_start.bsearch(s, false) - 1, 0, pt.seg_count - 1)


## 该路径上原始曲率（或坡度）在 [a, b] 上的积分；路径范围之外按 0 计。
func _integral(pt: PathTable, a: float, b: float, use_kappa: bool) -> float:
	return _prefix(pt, b, use_kappa) - _prefix(pt, a, use_kappa)


func _prefix(pt: PathTable, s: float, use_kappa: bool) -> float:
	s = clampf(s, 0.0, pt.total)
	var i := _seg_index(pt, s)
	if use_kappa:
		return pt.cum_kappa[i] + pt.seg_kappa[i] * (s - pt.seg_start[i])
	return pt.cum_grade[i] + pt.seg_grade[i] * (s - pt.seg_start[i])


## R-11：沿实际路线在 [s − T-21, s + T-21] 上取平均。
func _route_average(path_id: int, s: float, exit_armed: bool, from_access: bool, use_kappa: bool) -> float:
	var w: float = Tuning.d.t21_smooth_window_m
	if w <= 0.0:
		var pt0 := _pt[path_id]
		var i0 := _seg_index(pt0, s)
		return pt0.seg_kappa[i0] if use_kappa else pt0.seg_grade[i0]
	var total := 0.0
	# 前方
	var p := path_id
	var cur := s
	var rem := w
	while rem > 0.0:
		if p == PATH_MAIN:
			total += _integral(_pt[p], cur, cur + rem, use_kappa)
			break
		var bound := _pt[p].total
		var np := PATH_LOOP
		if p == PATH_LOOP and exit_armed and cur < fork_s:
			bound = fork_s
			np = PATH_MAIN
		var step := minf(rem, bound - cur)
		total += _integral(_pt[p], cur, cur + step, use_kappa)
		rem -= step
		if rem > 0.0:
			p = np
			cur = 0.0
	# 后方
	p = path_id
	cur = s
	rem = w
	while rem > 0.0:
		var step := minf(rem, cur)
		total += _integral(_pt[p], cur - step, cur, use_kappa)
		rem -= step
		if rem <= 0.0:
			break
		if p == PATH_ACCESS:
			break   # 出库路起点之前按直道计
		elif p == PATH_LOOP:
			if from_access:
				p = PATH_ACCESS
				cur = _pt[PATH_ACCESS].total
			else:
				cur = _pt[PATH_LOOP].total
		else:
			p = PATH_LOOP
			cur = fork_s
	return total / (2.0 * w)


# ───────────────────────── 网格（A-72） ─────────────────────────

func _build_meshes() -> void:
	var rv := PackedVector3Array()
	var rc := PackedColorArray()
	for p in 3:
		_build_road(p, rv, rc)
	for line_s in gate_s:
		_build_checker(line_s, rv, rc)
	road_mesh.mesh = _make_mesh(rv, rc)

	var gv := PackedVector3Array()
	var gc := PackedColorArray()
	var main_total := _pt[PATH_MAIN].total
	_build_ground(PATH_ACCESS, 0.0, _pt[PATH_ACCESS].total, SECTION_GROUND_Y[0], COL_GROUND[0], gv, gc)
	_build_ground(PATH_LOOP, 0.0, _pt[PATH_LOOP].total, SECTION_GROUND_Y[0], COL_GROUND[0], gv, gc)
	for i in section_names.size():
		var a := maxf(section_start[i] - GROUND_OVERLAP, 0.0)
		var b := section_start[i + 1] + GROUND_OVERLAP
		if i == section_names.size() - 1:
			b = main_total
		_build_ground(PATH_MAIN, a, minf(b, main_total), SECTION_GROUND_Y[i], COL_GROUND[i], gv, gc)
	var lake := main_data.seg_label.find(LAKE_SEG_LABEL)
	if lake >= 0:
		var mp := _pt[PATH_MAIN]
		_build_ground(PATH_MAIN, mp.seg_start[lake], mp.seg_start[lake + 1], LAKE_Y, COL_LAKE, gv, gc)
	ground_mesh.mesh = _make_mesh(gv, gc)


func _make_mesh(verts: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 所有世界模型共用的两级明暗材质（由 environment_director.gd 提供）。
func set_material(material: Material) -> void:
	road_mesh.material_override = material
	ground_mesh.material_override = material


func _quad(v: PackedVector3Array, c: PackedColorArray, a: Vector3, b: Vector3, d: Vector3, e: Vector3, col: Color) -> void:
	# a、b 在前一个截面，d、e 在后一个截面（a–d、b–e 同侧）
	v.append(a); v.append(b); v.append(e)
	v.append(a); v.append(e); v.append(d)
	for _i in 6:
		c.append(col)


## 横跨整个路面的黑白棋盘格带，CHECKER_ROWS 排，每格 CHECKER_SQUARE 米见方。
func _build_checker(line_s: float, v: PackedVector3Array, c: PackedColorArray) -> void:
	var up := Vector3(0.0, LINE_LIFT * 2.0, 0.0)
	var cols := int(ROAD_HALF_WIDTH * 2.0 / CHECKER_SQUARE)
	for row in CHECKER_ROWS:
		var xa := transform_at(PATH_MAIN, line_s + row * CHECKER_SQUARE)
		var xb := transform_at(PATH_MAIN, line_s + (row + 1) * CHECKER_SQUARE)
		var ra := right_at(PATH_MAIN, line_s + row * CHECKER_SQUARE)
		var rb := right_at(PATH_MAIN, line_s + (row + 1) * CHECKER_SQUARE)
		for col in cols:
			var l := -ROAD_HALF_WIDTH + col * CHECKER_SQUARE
			var r := l + CHECKER_SQUARE
			var color := COL_CENTER if (row + col) % 2 == 0 else COL_CHECKER_DARK
			_quad(v, c, xa.origin + ra * l + up, xa.origin + ra * r + up,
					xb.origin + rb * l + up, xb.origin + rb * r + up, color)


func _road_half(path_id: int, s: float) -> float:
	if path_id == PATH_ACCESS and s < GARAGE_DOOR_Y + GARAGE_TAPER:
		return lerpf(GARAGE_DOOR_HALF, ROAD_HALF_WIDTH, clampf((s - GARAGE_DOOR_Y) / GARAGE_TAPER, 0.0, 1.0))
	return ROAD_HALF_WIDTH


func _is_main_straight(path_id: int, seg: int) -> bool:
	return path_id == PATH_ACCESS or seg == 0


func _build_road(path_id: int, v: PackedVector3Array, c: PackedColorArray) -> void:
	var pt := _pt[path_id]
	var up_line := Vector3(0.0, LINE_LIFT, 0.0)
	var first := 0
	if path_id == PATH_ACCESS:
		first = int(GARAGE_DOOR_Y)   # 出库路的路面从大门开始画
	for i in range(first, pt.pos.size() - 1):
		var a := pt.pos[i]
		var b := pt.pos[i + 1]
		var ra := Vector3(cos(pt.yaw[i]), 0.0, sin(pt.yaw[i]))
		var rb := Vector3(cos(pt.yaw[i + 1]), 0.0, sin(pt.yaw[i + 1]))
		var ha := _road_half(path_id, pt.sample_s[i])
		var hb := _road_half(path_id, pt.sample_s[i + 1])
		_quad(v, c, a - ra * ha, a + ra * ha, b - rb * hb, b + rb * hb, COL_ROAD)

		# 车道线：路口重叠范围内只画主直道的（5.4）
		var seg := _seg_index(pt, pt.sample_s[i] + 0.5)
		var draw_lines := true
		if not _is_main_straight(path_id, seg):
			var y_north := -a.z
			if absf(a.x) < JUNCTION_CLEAR and y_north >= 0.0 and y_north <= MAIN_STRAIGHT_Y_MAX:
				draw_lines = false
		if draw_lines:
			var ia := ha - (ROAD_HALF_WIDTH - EDGE_LINE_INNER)
			var oa := ha - (ROAD_HALF_WIDTH - EDGE_LINE_OUTER)
			var ib := hb - (ROAD_HALF_WIDTH - EDGE_LINE_INNER)
			var ob := hb - (ROAD_HALF_WIDTH - EDGE_LINE_OUTER)
			for side: float in [-1.0, 1.0]:
				_quad(v, c, a + ra * side * ia + up_line, a + ra * side * oa + up_line,
						b + rb * side * ib + up_line, b + rb * side * ob + up_line, COL_EDGE)
			if i % DASH_PERIOD < DASH_LENGTH:
				_quad(v, c, a - ra * CENTER_LINE_HALF + up_line, a + ra * CENTER_LINE_HALF + up_line,
						b - rb * CENTER_LINE_HALF + up_line, b + rb * CENTER_LINE_HALF + up_line, COL_CENTER)

		# 路面抬高处：森林、冰原是 45° 路基；城市是高架护墙（5.4）
		if path_id == PATH_MAIN and (a.y > 0.02 or b.y > 0.02):
			var section := section_index_at(pt.sample_s[i])
			for side: float in [-1.0, 1.0]:
				var ea := a + ra * side * ha
				var eb := b + rb * side * hb
				if section < 2:
					var ga := SECTION_GROUND_Y[section] - 0.05
					var fa := ea + ra * side * (a.y - ga)
					var fb := eb + rb * side * (b.y - ga)
					fa.y = ga
					fb.y = ga
					_quad(v, c, ea, fa, eb, fb, COL_ROAD_DARK)
				else:
					var top := Vector3(0.0, PARAPET_HEIGHT, 0.0)
					var oa2 := ea + ra * side * PARAPET_THICK
					var ob2 := eb + rb * side * PARAPET_THICK
					_quad(v, c, ea, ea + top, eb, eb + top, COL_PARAPET)
					_quad(v, c, ea + top, oa2 + top, eb + top, ob2 + top, COL_PARAPET)
					_quad(v, c, oa2, oa2 + top, ob2, ob2 + top, COL_PARAPET)


func _build_ground(path_id: int, s_from: float, s_to: float, height: float, col: Color,
		v: PackedVector3Array, c: PackedColorArray) -> void:
	var pt := _pt[path_id]
	var have_prev := false
	var pl := Vector3.ZERO
	var pr := Vector3.ZERO
	var s := s_from
	while true:
		var i := mini(int(round(s)), pt.pos.size() - 1)
		var p := pt.pos[i]
		var r := Vector3(cos(pt.yaw[i]), 0.0, sin(pt.yaw[i]))
		var l := Vector3(p.x, height, p.z) - r * GROUND_HALF_WIDTH
		var rr := Vector3(p.x, height, p.z) + r * GROUND_HALF_WIDTH
		if have_prev:
			_quad(v, c, pl, pr, l, rr, col)
		pl = l
		pr = rr
		have_prev = true
		if s >= s_to:
			break
		s = minf(s + GROUND_STEP, s_to)


# ───────────────────────── 小地图用 ─────────────────────────

const ROUTE_STEP := 5.0
const SHARP_RADIUS := 150.0   ## 5.6：半径 ≤ 150 m 的圆弧在小地图上加粗

## 从采样表里切出前方 dist 米给小地图（5.6、11.8）：
## main = 主路线的 3D 点列（每 5 m 一点）；sharp = 每个点是否在急弯上；
## lines = 区段线距车的距离；branch = 岔路口另一支的 3D 点列（没有岔路口时为空）。
func route_ahead(path_id: int, s: float, dist: float, exit_armed := false, from_access := false) -> Dictionary:
	var main := PackedVector3Array()
	var sharp := PackedByteArray()
	var lines := PackedFloat32Array()
	var branch := PackedVector3Array()
	var prev: Array = [path_id, s]
	var d := 0.0
	while d <= dist:
		var loc := advance(path_id, s, d, exit_armed, from_access)
		var p: int = loc[0]
		var ls: float = loc[1]
		main.append(transform_at(p, ls).origin)
		var pt := _pt[p]
		var k := absf(pt.seg_kappa[_seg_index(pt, ls)])
		sharp.append(1 if (k > 0.0 and 1.0 / k <= SHARP_RADIUS) else 0)
		if d > 0.0:
			var prev_p: int = prev[0]
			var prev_s: float = prev[1]
			if p == PATH_MAIN:
				var from_s := prev_s if prev_p == PATH_MAIN else -1.0
				for line_s in gate_s:
					if line_s > from_s and line_s <= ls:
						lines.append(d - (ls - line_s))
			# 岔路口：画出没走的那一支
			var other_path := -1
			var other_s := 0.0
			if prev_p == PATH_LOOP and p == PATH_MAIN:
				other_path = PATH_LOOP
				other_s = fork_s
			elif prev_p == PATH_LOOP and p == PATH_LOOP and prev_s < fork_s and ls >= fork_s:
				other_path = PATH_MAIN
			if other_path >= 0 and branch.is_empty():
				var e := 0.0
				while e <= dist - d:
					var bl := advance(other_path, other_s, e, false, false)
					branch.append(transform_at(bl[0], bl[1]).origin)
					e += ROUTE_STEP
		prev = loc
		d += ROUTE_STEP
	return {"main": main, "sharp": sharp, "lines": lines, "branch": branch, "step": ROUTE_STEP}
