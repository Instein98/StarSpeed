class_name Ghost
extends Node3D
## 最好成绩的"幽灵"和实时差值（开发者 2026-11-19 第 1 轮 #2、#3）。
## 计时赛里每个区段每 STEP 米记一次"本区段已用时间"。区段刷新最好成绩时（或这个区段还没有记录时）
## 把这条曲线存到 user://ghost.json。之后再跑这个区段：
##   - 实时差值 = 本区段已用时间 − 最好那趟到达同一位置的时间（负数 = 比最好快），右上角显示；
##   - 幽灵 = 最好那趟在"同样的已用时间"时所在的位置，路面上画一个半透明的车形，小地图上画一个点。
## 设置里可以关掉幽灵（存档 ghost_on），差值一直显示。

const STEP := 10.0
const PATH := "user://ghost.json"
const COL := Color(0.45, 0.85, 1.0, 0.45)
const LIFT := 0.05

var main: Node
var car: CarSim
var track: Track
## 测试时改成别的路径，免得覆盖开发者的记录
var save_path := PATH
## 最好那趟的曲线：每个区段一个 PackedFloat32Array（第 k 项 = 到达 区段起点 + k×STEP 时的已用时间）
var best: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
## 实时差值（秒）；没有可比的记录时为 NAN
var delta := NAN
## 幽灵在主赛道上的里程；不显示时为 −1
var ghost_s := -1.0

var _cur: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
var _section := -1
var _body: MeshInstance3D


func setup(p_main: Node, p_car: CarSim, p_track: Track) -> void:
	main = p_main
	car = p_car
	track = p_track
	_load()
	_body = MeshInstance3D.new()
	_body.mesh = _build_mesh()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = COL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_body.material_override = m
	_body.visible = false
	add_child(_body)


func _process(_delta: float) -> void:
	if car == null:
		return
	var sec: int = main._timing_section
	if sec != _section:
		_section = sec
		if sec >= 0:
			_cur[sec] = PackedFloat32Array()
	delta = NAN
	ghost_s = -1.0
	var timing: bool = sec >= 0 and car.path_id == Track.PATH_MAIN and main.flow.state == RunFlow.State.RUN
	if timing:
		var t: float = main._section_time
		var x: float = car.s - track.gate_s[sec]
		# 记录：第一次到达每个标记点时的已用时间（复位倒退后再经过不覆盖）
		var c: PackedFloat32Array = _cur[sec]
		while x >= c.size() * STEP:
			c.append(t)
		_cur[sec] = c
		var b: PackedFloat32Array = best[sec]
		if b.size() >= 2:
			delta = t - _time_at(b, x)
			ghost_s = track.gate_s[sec] + _dist_at(b, t)
	var show := ghost_s >= 0.0 and bool(SaveData.data.get("ghost_on", true)) and ghost_s > car.s + 2.0
	_body.visible = show
	if show:
		var xf := track.transform_at(Track.PATH_MAIN, ghost_s)
		xf.origin += xf.basis.y * LIFT
		_body.global_transform = xf


## 区段跑完（main 在 flow.section_done 之后调用）：刷新了最好成绩或者还没有记录时存这条曲线。
func section_finished(index: int, record: bool) -> void:
	var c: PackedFloat32Array = _cur[index]
	var need := int((track.gate_s[index + 1] - track.gate_s[index]) / STEP)
	if c.size() < need:
		return          # 不完整（例如 F4 瞬移进来的），不存
	if record or (best[index] as PackedFloat32Array).size() < 2:
		best[index] = c.duplicate()
		_save()


## 曲线上到达距离 x 时的已用时间（线性插值）。
static func _time_at(b: PackedFloat32Array, x: float) -> float:
	var k := clampf(x / STEP, 0.0, b.size() - 1.0)
	var i := mini(int(k), b.size() - 2)
	return lerpf(b[i], b[i + 1], k - i)


## 曲线上已用时间为 t 时走过的距离（线性插值；曲线单调不减）。
static func _dist_at(b: PackedFloat32Array, t: float) -> float:
	if t <= b[0]:
		return 0.0
	var lo := 0
	var hi := b.size() - 1
	if t >= b[hi]:
		return hi * STEP
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if b[mid] <= t:
			lo = mid
		else:
			hi = mid
	var span := b[hi] - b[lo]
	return (lo + (0.0 if span <= 0.0 else (t - b[lo]) / span)) * STEP


func _load() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not (data is Dictionary) or not data.has("sections"):
		return
	var secs: Array = data["sections"]
	for i in mini(secs.size(), 3):
		best[i] = PackedFloat32Array(secs[i] as Array)


func _save() -> void:
	var secs := []
	for b: PackedFloat32Array in best:
		var arr := []
		for v in b:
			arr.append(snappedf(v, 0.001))
		secs.append(arr)
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"version": 1, "step": STEP, "sections": secs}))


## 半透明的车形：车身 2 × 4.4 m、高 0.7 m，上面一个座舱。原点在车的中心，朝 −Z。
static func _build_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	var c := Color.WHITE
	k.box(Vector3(0, 0.45, 0), Vector3(2.0, 0.7, 4.4), c)
	k.box(Vector3(0, 1.05, 0.3), Vector3(1.5, 0.5, 2.0), c)
	return k.build()
