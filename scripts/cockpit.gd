class_name Cockpit
extends Node3D
## 座舱：指针、档位数字、换挡提示灯、降档提示灯、方向盘转角（规格 5.7、9.4、9.5、11.4）。
## 第 8.4a 节：现在所有部件都是用引擎自带的方块、圆盘、圆环和 Label3D 拼的临时替身
## （_build_placeholders）；节点名与第 11.3 节一致，之后换成真模型时删掉那个函数即可。
## 坐标：座舱原点在驾驶员眼睛正下方 1.05 m；+X 向右，−Z 向前。

const EYE := Vector3(0.0, 1.05, 0.0)

# 第 9.5 节的三维位置（以眼睛为原点：前，右，上）
const TACH_POS := Vector3(0.0, -0.18, -0.51)
const TACH_RADIUS := 0.095
const WHEEL_POS := Vector3(0.0, -0.21, -0.32)
const WHEEL_RADIUS := 0.18
const WHEEL_RIM := 0.016            ## 画面上轮圈粗 26 像素
const WHEEL_TILT_DEG := 20.0
const DASH_TOP := -0.14
const DASH_FRONT := 0.53            ## 仪表台前沿（比转速表略远，让表露出来）
const DASH_DEPTH := 0.25
const ROOF_BOTTOM := 0.35
const SHELL_FORWARD := 0.6
const SHELL_HALF_WIDTH := 1.2
const SHELL_TOP := 1.0
const FRAME_INNER := 0.672          ## 左右窗框占画面最外侧 5%
const MINIMAP_ANCHOR := Vector3(0.0, -0.01, -0.60)

# 转速表（9.4）
const NEEDLE_MIN_DEG := -135.0
const NEEDLE_MAX_DEG := 135.0
const RPM_MAX := 9000.0
const NEEDLE_SMOOTH := 0.04         ## 5.2
const LIMITER_JITTER_LOW := 8700.0  ## R-08
const LIMITER_JITTER_HZ := 12.0
const LAMP_BLINK_HZ := 6.0          ## R-09a
const LAMP_BURST_MIN_HZ := 12.0
const LAMP_BURST_MAX_HZ := 20.0
const GEAR_BLINK_HZ := 6.0

# 方向盘（5.7）
const STEER_DEG_PER_KAPPA := 1500.0
const STEER_MAX_DEG := 45.0
const STEER_SMOOTH := 0.1
const STEER_SHAKE_DEG := 2.0
const STEER_SHAKE_HZ := 25.0

const COL_DARK := Color("1b2233")
const COL_DARKER := Color("0f1424")
const COL_NAVY := Color("2b3550")
const COL_ROAD := Color("4a5262")
const COL_GREY := Color("8a93a3")
const COL_RED := Color("ef4a2f")
const COL_RED_DARK := Color("b5371f")
const COL_GOLD := Color("ffc93c")
const COL_WHITE := Color("f7ecd4")
const COL_SKY := Color("4fb8e6")

var car: CarSim
var material: ShaderMaterial
var game_time := 0.0
## 爆缸演出中：指针打到表盘尽头并卡住，换挡提示灯常亮（7.3）
const BLOWN_SWEEP_RPM_PER_SEC := 7000.0
var blown := false

var _needle_rpm := 0.0
var _steer_deg := 0.0
var _lamp_phase := 0.0
var _lamp_on_mesh: Mesh
var _lamp_off_mesh: Mesh
var _downshift_lamp: MeshInstance3D

@onready var shell: MeshInstance3D = $Shell
@onready var dash: MeshInstance3D = $Dash
@onready var tach: Node3D = $Tach
@onready var tach_body: MeshInstance3D = $Tach/TachBody
@onready var needle: MeshInstance3D = $Tach/Needle
@onready var gear_label: Label3D = $Tach/GearLabel
@onready var shift_lamp: MeshInstance3D = $Tach/ShiftLamp
@onready var wheel: Node3D = $Wheel
@onready var wheel_mesh: MeshInstance3D = $Wheel/WheelMesh
@onready var minimap_anchor: Marker3D = $MinimapAnchor


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = EnvironmentDirector.FLAT2TONE
	# 8.2：座舱的光向固定为左前上方、仰角 60°，不随环境变
	var az := deg_to_rad(-45.0)
	var el := deg_to_rad(60.0)
	material.set_shader_parameter("light_dir", Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)))
	_build_placeholders()
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = material
	_needle_rpm = Tuning.d.t03_idle_rpm


## 光色取当前环境的光色；亮度点火前 0.15、点火后 1.0（阶段 5 接入）。
func set_light(color: Color, brightness: float) -> void:
	material.set_shader_parameter("light_color", Vector3(color.r, color.g, color.b))
	material.set_shader_parameter("brightness", brightness)


## 方向盘当前转角（度，左转为正）；小地图的箭头倾斜用。
func steer_angle_deg() -> float:
	return _steer_deg


func _process(delta: float) -> void:
	if car == null:
		return
	game_time += delta
	var t := Tuning.d

	# 指针：平时显示 0.04 秒平滑的 rpm；换挡扫动和断油抖动直接驱动（5.2、R-08）
	var shown := 0.0
	if blown:
		# 爆缸：指针很快地扫到尽头卡住（不是瞬移），速度和引擎声的转速扫动一致
		_needle_rpm = move_toward(_needle_rpm, RPM_MAX, BLOWN_SWEEP_RPM_PER_SEC * delta)
		shown = _needle_rpm
	elif car.shifting:
		shown = lerpf(car.shift_rpm_from, car.rpm, car.shift_progress)
		_needle_rpm = shown
	elif car.rpm >= t.t05_cut_rpm:
		var tri := absf(fposmod(game_time * LIMITER_JITTER_HZ, 1.0) * 2.0 - 1.0)
		shown = lerpf(LIMITER_JITTER_LOW, t.t05_cut_rpm, tri)
		_needle_rpm = t.t05_cut_rpm
	else:
		_needle_rpm += (car.rpm - _needle_rpm) * (1.0 - exp(-delta / NEEDLE_SMOOTH))
		shown = _needle_rpm
	var deg := lerpf(NEEDLE_MIN_DEG, NEEDLE_MAX_DEG, clampf(shown / RPM_MAX, 0.0, 1.0))
	needle.rotation = Vector3(0.0, 0.0, -deg_to_rad(deg))

	# 档位数字：换挡开始那一帧就是新档位；断油时变朱红并以 6 Hz 闪烁
	gear_label.text = str(car.gear)
	if car.limiter_active:
		gear_label.modulate = COL_RED
		gear_label.visible = fposmod(game_time * GEAR_BLINK_HZ, 1.0) < 0.5
	else:
		gear_label.modulate = COL_GOLD
		gear_label.visible = true

	# 换挡提示灯（R-09a）
	var lit := false
	match car.lamp_mode:
		CarSim.Lamp.BLINK:
			_lamp_phase = fposmod(_lamp_phase + delta * LAMP_BLINK_HZ, 1.0)
			lit = _lamp_phase < 0.5
		CarSim.Lamp.BURST:
			var hz := LAMP_BURST_MIN_HZ
			if car.gear < t.t01_gear_count:
				hz = lerpf(LAMP_BURST_MIN_HZ, LAMP_BURST_MAX_HZ, clampf(car.overrev_timer / t.t11_overrev_limit, 0.0, 1.0))
			_lamp_phase = fposmod(_lamp_phase + delta * hz, 1.0)
			lit = _lamp_phase < 0.5
		_:
			_lamp_phase = 0.0
	shift_lamp.mesh = _lamp_on_mesh if (lit or blown) else _lamp_off_mesh

	# 降档提示灯（R-06a，辅助开关，默认关；开关在阶段 6 的键位设置里）
	var assist: bool = SaveData.data.get("assist_downshift_lamp", false)
	_downshift_lamp.visible = assist and car.gear > 1 and not car.shifting \
			and car.rpm_for(car.v, car.gear - 1) <= t.t59_downshift_lamp_rpm

	# 方向盘：转角 = clamp(κ × 1500°, ±45°)，左弯向左转；第三段和挣扎区叠加 ±2° 的 25 Hz 抖动
	var target := clampf(car.kappa * STEER_DEG_PER_KAPPA, -STEER_MAX_DEG, STEER_MAX_DEG)
	_steer_deg += (target - _steer_deg) * (1.0 - exp(-delta / STEER_SMOOTH))
	var shake := 0.0
	if car.tire_zone >= CarSim.Zone.THREE:
		shake = STEER_SHAKE_DEG * sin(game_time * TAU * STEER_SHAKE_HZ)
	wheel.basis = Basis(Vector3.RIGHT, deg_to_rad(-WHEEL_TILT_DEG)) * Basis(Vector3.BACK, deg_to_rad(_steer_deg + shake))


# ───────────────────────── 临时替身（真模型到位后删除） ─────────────────────────

class Parts:
	extends RefCounted
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## 把一个引擎自带的基础网格按 xf 摆进来，整体涂成 color（alpha = 0 表示自发光）。
	func add(mesh: PrimitiveMesh, xf: Transform3D, color: Color) -> void:
		var arrays := mesh.get_mesh_arrays()
		var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := verts.size()
		for p in src:
			verts.append(xf * p)
			colors.append(color)
		for i in idx:
			indices.append(base + i)

	func box(size: Vector3, xf: Transform3D, color: Color) -> void:
		var m := BoxMesh.new()
		m.size = size
		add(m, xf, color)

	func build() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


static func _at(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, pos)


## 圆盘 / 圆环的轴从 Y 转到 Z（面朝驾驶员）。
static func _facing(pos: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, PI * 0.5), pos)


## 表盘上的位置：从 12 点方向顺时针 deg 度、半径 r 处，朝外的方向为局部 +Y。
static func _dial(deg: float, r: float, z: float) -> Transform3D:
	var b := Basis(Vector3.BACK, -deg_to_rad(deg))
	return Transform3D(b, b * Vector3(0.0, r, 0.0) + Vector3(0.0, 0.0, z))


static func _emissive(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.0)


func _build_placeholders() -> void:
	# 外壳 A-01：车顶压在画面上 8%，左右窗框各占最外侧 5%，没有 A 柱
	var p := Parts.new()
	var roof_h := SHELL_TOP - ROOF_BOTTOM
	p.box(Vector3(SHELL_HALF_WIDTH * 2.0, roof_h, 0.05),
			_at(EYE + Vector3(0.0, ROOF_BOTTOM + roof_h * 0.5, -SHELL_FORWARD)), COL_DARK)
	var frame_w := SHELL_HALF_WIDTH - FRAME_INNER
	var frame_h := ROOF_BOTTOM - DASH_TOP
	for side: float in [-1.0, 1.0]:
		p.box(Vector3(frame_w, frame_h, 0.05),
				_at(EYE + Vector3(side * (FRAME_INNER + frame_w * 0.5), DASH_TOP + frame_h * 0.5, -SHELL_FORWARD)), COL_DARK)
	shell.mesh = p.build()

	# 仪表台 A-02：深蓝黑，上沿一条朱红细线
	p = Parts.new()
	var dash_h := EYE.y + DASH_TOP
	p.box(Vector3(SHELL_HALF_WIDTH * 2.0, dash_h, DASH_DEPTH),
			_at(Vector3(0.0, dash_h * 0.5, -(DASH_FRONT + DASH_DEPTH * 0.5))), COL_DARK)
	p.box(Vector3(SHELL_HALF_WIDTH * 2.0, 0.006, 0.006),
			_at(Vector3(0.0, dash_h + 0.003, -DASH_FRONT)), COL_RED)
	dash.mesh = p.build()

	# 转速表 A-05：正对眼睛
	var r := TACH_RADIUS
	tach.transform = Transform3D(Basis.looking_at(TACH_POS, Vector3.UP), EYE + TACH_POS)
	p = Parts.new()
	var disc := CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.004
	disc.radial_segments = 48
	disc.rings = 1
	p.add(disc, _facing(Vector3(0.0, 0.0, -0.002)), COL_DARK)
	var bezel := TorusMesh.new()          # 表圈：楼灰，宽为表盘半径的 8%
	bezel.inner_radius = r
	bezel.outer_radius = r * 1.08
	bezel.rings = 48
	bezel.ring_segments = 6
	p.add(bezel, _facing(Vector3.ZERO), COL_GREY)
	var red_ring := TorusMesh.new()       # 表圈内侧一圈朱红细线
	red_ring.inner_radius = r * 0.985
	red_ring.outer_radius = r
	red_ring.rings = 48
	red_ring.ring_segments = 4
	p.add(red_ring, _facing(Vector3(0.0, 0.0, 0.0005)), COL_RED)
	var tick_outer := r * 0.93
	for rpm in range(0, int(RPM_MAX) + 1, 200):
		var deg := lerpf(NEEDLE_MIN_DEG, NEEDLE_MAX_DEG, rpm / RPM_MAX)
		var major := rpm % 1000 == 0
		var best: bool = rpm == int(Tuning.d.t06_best_shift_rpm)   # 最佳升档标记：金黄、加长
		var length := r * (0.14 if (major or best) else 0.07)
		var width := tick_outer * deg_to_rad(1.5 if major else 0.6)
		p.box(Vector3(width, length, 0.0006), _dial(deg, tick_outer - length * 0.5, 0.0005),
				COL_GOLD if best else COL_WHITE)
	# 红区：8000–9000 转沿刻度外缘的朱红弧，宽为半径的 6%
	var red_from := lerpf(NEEDLE_MIN_DEG, NEEDLE_MAX_DEG, Tuning.d.t04_redline_rpm / RPM_MAX)
	for i in 10:
		var deg := lerpf(red_from, NEEDLE_MAX_DEG, (i + 0.5) / 10.0)
		var seg_w := r * 0.97 * deg_to_rad((NEEDLE_MAX_DEG - red_from) / 10.0) * 1.1
		p.box(Vector3(seg_w, r * 0.06, 0.0006), _dial(deg, r * 0.965, 0.0004), COL_RED)
	# 档位窗：表盘中心正下方半径 45% 处，楼蓝黑底、暖白细框
	p.box(Vector3(r * 0.36, r * 0.44, 0.0004), _at(Vector3(0.0, -r * 0.45, 0.0004)), COL_WHITE)
	p.box(Vector3(r * 0.32, r * 0.40, 0.0004), _at(Vector3(0.0, -r * 0.45, 0.0007)), COL_NAVY)
	tach_body.mesh = p.build()

	# 数字 0–9（8 和 9 为朱红）和单位字样：Label3D
	for n in 10:
		var deg := lerpf(NEEDLE_MIN_DEG, NEEDLE_MAX_DEG, n * 1000.0 / RPM_MAX)
		var label := _make_label(str(n), r * 0.16, COL_RED if n >= 8 else COL_WHITE)
		label.position = _dial(deg, r * 0.66, 0.001).origin
		tach_body.add_child(label)
	var unit := _make_label("×1000 r/min", r * 0.07, COL_WHITE)
	unit.position = Vector3(0.0, r * 0.30, 0.001)
	tach_body.add_child(unit)

	# 指针：朱红自发光，根部宽、尖端细，原点在转轴上；暖白轴盖
	p = Parts.new()
	var needle_len := tick_outer - r * 0.14
	var prism := PrismMesh.new()
	prism.size = Vector3(r * 0.07, needle_len, 0.0006)
	p.add(prism, _at(Vector3(0.0, needle_len * 0.5, 0.0015)), _emissive(COL_RED))
	var cap := CylinderMesh.new()
	cap.top_radius = r * 0.07
	cap.bottom_radius = r * 0.07
	cap.height = 0.001
	cap.radial_segments = 16
	cap.rings = 1
	p.add(cap, _facing(Vector3(0.0, 0.0, 0.002)), COL_WHITE)
	needle.mesh = p.build()

	# 档位数字：金黄，字高为半径的 34%
	_setup_label(gear_label, "1", r * 0.34, COL_GOLD)
	gear_label.position = Vector3(0.0, -r * 0.45, 0.0012)

	# 换挡提示灯 A-06：表圈顶端，直径为表盘半径的 14%；亮时自发光朱红，灭时暗朱红
	var lamp := CylinderMesh.new()
	lamp.top_radius = r * 0.07
	lamp.bottom_radius = r * 0.07
	lamp.height = 0.003
	lamp.radial_segments = 16
	lamp.rings = 1
	var seat := CylinderMesh.new()
	seat.top_radius = r * 0.095
	seat.bottom_radius = r * 0.095
	seat.height = 0.002
	seat.radial_segments = 16
	seat.rings = 1
	for lit: bool in [true, false]:
		p = Parts.new()
		p.add(seat, _facing(Vector3.ZERO), COL_GREY)
		p.add(lamp, _facing(Vector3(0.0, 0.0, 0.001)), _emissive(COL_RED) if lit else COL_RED_DARK)
		if lit:
			_lamp_on_mesh = p.build()
		else:
			_lamp_off_mesh = p.build()
	shift_lamp.mesh = _lamp_off_mesh
	shift_lamp.position = Vector3(0.0, r * 1.04, 0.003)

	# 降档提示灯：档位窗右侧的晴空蓝小圆灯，直径为表盘半径的 8%
	var blue := CylinderMesh.new()
	blue.top_radius = r * 0.04
	blue.bottom_radius = r * 0.04
	blue.height = 0.001
	blue.radial_segments = 12
	blue.rings = 1
	p = Parts.new()
	p.add(blue, _facing(Vector3.ZERO), _emissive(COL_SKY))
	_downshift_lamp = MeshInstance3D.new()
	_downshift_lamp.name = "DownshiftLamp"
	_downshift_lamp.mesh = p.build()
	_downshift_lamp.position = Vector3(r * 0.26, -r * 0.45, 0.0012)
	_downshift_lamp.visible = false
	tach.add_child(_downshift_lamp)

	# 方向盘 A-03：完整的圆形轮圈，三根辐条（9 点、3 点、6 点），中央六边形盖板
	wheel.position = EYE + WHEEL_POS
	p = Parts.new()
	var rim := TorusMesh.new()
	rim.inner_radius = WHEEL_RADIUS - WHEEL_RIM
	rim.outer_radius = WHEEL_RADIUS
	rim.rings = 48
	rim.ring_segments = 8
	p.add(rim, _facing(Vector3.ZERO), COL_NAVY)
	var spoke_len := WHEEL_RADIUS - WHEEL_RIM * 0.5
	for deg: float in [90.0, 270.0, 180.0]:
		p.box(Vector3(0.022, spoke_len, 0.008), _dial(deg, spoke_len * 0.5, 0.0), COL_ROAD)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.04
	hub.bottom_radius = 0.04
	hub.height = 0.012
	hub.radial_segments = 6
	hub.rings = 1
	p.add(hub, _facing(Vector3(0.0, 0.0, 0.004)), COL_DARKER)
	var star := CylinderMesh.new()       # 盖板上的金黄色星形标（替身用小圆片）
	star.top_radius = 0.012
	star.bottom_radius = 0.012
	star.height = 0.002
	star.radial_segments = 5
	star.rings = 1
	p.add(star, _facing(Vector3(0.0, 0.0, 0.011)), COL_GOLD)
	wheel_mesh.mesh = p.build()

	minimap_anchor.position = EYE + MINIMAP_ANCHOR


func _make_label(text: String, height: float, color: Color) -> Label3D:
	var label := Label3D.new()
	_setup_label(label, text, height, color)
	return label


## 11.2：3D 文字用"裁剪透明"模式、关闭描边和阴影，作为不透明物体渲染，进入后处理。
func _setup_label(label: Label3D, text: String, height: float, color: Color) -> void:
	label.text = text
	label.font_size = 64
	label.pixel_size = height / (64.0 * 0.72)
	label.outline_size = 0
	label.modulate = color
	label.shaded = false
	label.double_sided = true
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
