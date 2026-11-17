class_name StickerDisplay
extends Node3D
## 挡风玻璃内侧右边的三枚奖牌贴纸（规格 5.8）：从上到下森林、冰原、城市。
## 临时替身：扁圆片 + 边圈 + 平的图案剪影，都用引擎自带几何体拼。
## 等级 0 = 没拿过（金黄细虚线圈），1 塑料、2 铜、3 银、4 金。
## 高光：一条暖白高光带每 3 秒从左上到右下扫过（塑料没有）；金牌另有一个四角星闪光点，每 3 秒在边圈上闪 0.2 秒。
## 贴上的特效（9.6）：金黄光环从 0 扩到约 120 像素后消失，贴纸从 1.6 倍缩到 1.0 倍，8 片暖白小三角向外迸出。
## 盘面和边圈用自发光：贴纸背着座舱的光，按两级明暗会落到暗面，金色压色板后会变成铜色。

const RADIUS := 0.035                 ## 直径 7 cm
const RIM := 0.004
const THICK := 0.002
const POS_TOP := Vector3(0.55, 0.20, -0.58)    ## 相对眼睛，第一枚的位置
const SPACING := 0.085
const POP_TIME := 0.35
const POP_SCALE := 1.6
const SHINE_EVERY := 3.0
const SHINE_TIME := 0.5
const SWEEP_FAST := 0.25
const SHINE_WIDTH := 0.007
const GLINT_TIME := 0.2
const GLINT_ARM := 0.012
const APPEAR_TIME := 0.3
const HALO_RADIUS := 0.09         ## 约 120 像素直径
const SHARD_TRAVEL := 0.03        ## 约 40 像素
const COL_WARM := Color(0.969, 0.925, 0.831, 0.0)   ## 自发光暖白
const COL_HALO := Color(1.0, 0.788, 0.235, 0.0)
const COL_WHITE := Color(1.0, 1.0, 1.0, 0.0)

const COL_DARK := Color("1b2233")
const COL_GOLD := Color("ffc93c")
## 盘面 / 边圈（5.8）
const PLATE := [Color(), Color("4fb8e6"), Color("8a4f22"), Color("8a93a3"), Color("ffc93c")]
const EDGE := [Color(), Color("8a93a3"), Color("c57a3a"), Color("c9d1dc"), Color("f7ecd4")]
const TIER_NAMES := ["", "塑料", "铜", "银", "金"]

var material: Material
var _slots: Array[MeshInstance3D] = []
var _pop: Array[float] = [1.0, 1.0, 1.0]
var _tiers: Array[int] = [0, 0, 0]
var _fx: Array[MeshInstance3D] = []
var _sweep: Array[float] = [-1.0, -1.0, -1.0]     ## 高光带的进度 0–1，< 0 = 没在扫
var _sweep_len: Array[float] = [SHINE_TIME, SHINE_TIME, SHINE_TIME]
var _glint: Array[float] = [-1.0, -1.0, -1.0]
var _glint_angle: Array[float] = [0.0, 0.0, 0.0]
var _appear: Array[float] = [-1.0, -1.0, -1.0]
var _clock := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_material: Material, eye: Vector3) -> void:
	material = p_material
	_eye = eye
	for i in 3:
		var m := MeshInstance3D.new()
		m.position = eye + POS_TOP + Vector3(0.0, -SPACING * i, 0.0)
		m.material_override = material
		add_child(m)
		_slots.append(m)
		var fx := MeshInstance3D.new()
		fx.material_override = material
		m.add_child(fx)
		_fx.append(fx)


## 换成某个等级；animate = 刚刚拿到，弹一下。
func set_tier(index: int, tier: int, animate := false) -> void:
	_slots[index].mesh = _build(index, tier)
	_tiers[index] = tier
	if animate:
		_pop[index] = 0.0
		_appear[index] = 0.0


## 结尾时放大到 1.5 倍，间距按比例放大（以中间那枚为中心）。
var zoom := 1.0
var _eye := Vector3.ZERO


func _process(delta: float) -> void:
	_update_fx(delta)
	for i in _slots.size():
		if _pop[i] < 1.0:
			_pop[i] = minf(1.0, _pop[i] + delta / POP_TIME)
		var u := _pop[i]
		var k := lerpf(POP_SCALE, 1.0, 1.0 - pow(1.0 - u, 3.0))
		_slots[i].scale = Vector3.ONE * k * zoom
		var center := _eye + POS_TOP + Vector3(0.0, -SPACING, 0.0)
		_slots[i].position = center + Vector3(0.0, -SPACING * (i - 1) * zoom, 0.0)


## 一条高光快速扫过这枚贴纸（9.6：本次等级不高于已有贴纸时；结尾里森林和冰原的贴纸）。
func sweep(index: int) -> void:
	_sweep[index] = 0.0
	_sweep_len[index] = SWEEP_FAST


func _update_fx(delta: float) -> void:
	var prev := _clock
	_clock += delta
	var tick := floorf(_clock / SHINE_EVERY) > floorf(prev / SHINE_EVERY)
	for i in 3:
		if tick and _tiers[i] >= 2 and _sweep[i] < 0.0:
			_sweep[i] = 0.0
			_sweep_len[i] = SHINE_TIME
		if tick and _tiers[i] == 4:
			_glint[i] = 0.0
			_glint_angle[i] = _rng.randf() * TAU
		var k := MeshKit.new()
		if _sweep[i] >= 0.0:
			_sweep[i] += delta / _sweep_len[i]
			if _sweep[i] >= 1.0:
				_sweep[i] = -1.0
			else:
				_band(k, lerpf(-RADIUS, RADIUS, _sweep[i]))
		if _glint[i] >= 0.0:
			_glint[i] += delta / GLINT_TIME
			if _glint[i] >= 1.0:
				_glint[i] = -1.0
			else:
				_star(k, _glint_angle[i], sin(PI * _glint[i]))
		if _appear[i] >= 0.0:
			_appear[i] += delta / APPEAR_TIME
			if _appear[i] >= 1.0:
				_appear[i] = -1.0
			else:
				_burst(k, _appear[i])
		_fx[i].mesh = k.build() if k.verts.size() > 0 else null


## 高光带：垂直于左上→右下方向的一条窄带，与盘面圆取交。o = 带中心沿该方向的位置。
func _band(k: MeshKit, o: float) -> void:
	var r := RADIUS - RIM
	var n := Vector3(1.0, -1.0, 0.0).normalized()
	var t := Vector3(1.0, 1.0, 0.0).normalized()
	var z := Vector3(0.0, 0.0, THICK * 1.3)
	var a := clampf(o - SHINE_WIDTH * 0.5, -r, r)
	var b := clampf(o + SHINE_WIDTH * 0.5, -r, r)
	if b - a < 1e-5:
		return
	var steps := 3
	for s in steps:
		var o0 := lerpf(a, b, float(s) / steps)
		var o1 := lerpf(a, b, float(s + 1) / steps)
		var h0 := sqrt(maxf(r * r - o0 * o0, 0.0))
		var h1 := sqrt(maxf(r * r - o1 * o1, 0.0))
		k.quad(n * o0 - t * h0 + z, n * o1 - t * h1 + z, n * o1 + t * h1 + z, n * o0 + t * h0 + z, COL_WARM)


## 四角星闪光点：边圈上 angle 处，大小 s（0–1）。
func _star(k: MeshKit, angle: float, s: float) -> void:
	var c := Vector3(cos(angle), sin(angle), 0.0) * (RADIUS - RIM * 0.5) + Vector3(0.0, 0.0, THICK * 1.5)
	var l := GLINT_ARM * s
	var w := l * 0.18
	k.quad(c + Vector3(-l, 0, 0), c + Vector3(0, -w, 0), c + Vector3(l, 0, 0), c + Vector3(0, w, 0), COL_WHITE)
	k.quad(c + Vector3(0, -l, 0), c + Vector3(w, 0, 0), c + Vector3(0, l, 0), c + Vector3(-w, 0, 0), COL_WHITE)


## 贴上的特效：金黄光环从 0 扩到 HALO_RADIUS 后消失；8 片暖白小三角从边缘向外迸出。u = 0–1。
func _burst(k: MeshKit, u: float) -> void:
	var z := Vector3(0.0, 0.0, THICK * 2.0)
	var r := HALO_RADIUS * u
	var w := 0.007 * (1.0 - u * 0.5)
	var seg := 32
	for j in seg:
		var a0 := TAU * j / seg
		var a1 := TAU * (j + 1) / seg
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		k.quad(d0 * r + z, d1 * r + z, d1 * (r + w) + z, d0 * (r + w) + z, COL_HALO)
	var size := 0.007 * (1.0 - u)
	for j in 8:
		var a := TAU * (j + 0.5) / 8.0
		var d := Vector3(cos(a), sin(a), 0.0)
		var side := Vector3(-d.y, d.x, 0.0)
		var p := d * (RADIUS + SHARD_TRAVEL * u) + z
		k.tri(p + d * size, p - d * size * 0.5 + side * size * 0.6, p - d * size * 0.5 - side * size * 0.6, COL_WARM)


static func _build(index: int, tier: int) -> ArrayMesh:
	var p := Cockpit.Parts.new()
	if tier <= 0:
		# 空位：一圈金黄色的细虚线
		for k in 16:
			var a := TAU * k / 16.0
			var xf := Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a), sin(a), 0.0) * (RADIUS - RIM * 0.5))
			p.box(Vector3(RIM * 0.6, RADIUS * 0.22, THICK), xf, Cockpit._emissive(COL_GOLD))
		return p.build()
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS - RIM
	disc.bottom_radius = RADIUS - RIM
	disc.height = THICK
	disc.radial_segments = 24
	disc.rings = 1
	p.add(disc, Cockpit._facing(Vector3.ZERO), Cockpit._emissive(PLATE[tier]))
	var rim := TorusMesh.new()
	rim.inner_radius = RADIUS - RIM
	rim.outer_radius = RADIUS
	rim.rings = 24
	rim.ring_segments = 6
	p.add(rim, Cockpit._facing(Vector3(0.0, 0.0, THICK * 0.5)), Cockpit._emissive(EDGE[tier]))
	var z := THICK * 0.6
	match index:
		0:   # 森林：三棵松树
			for x: float in [-0.013, 0.0, 0.013]:
				var h := 0.024 if x == 0.0 else 0.018
				_tri(p, Vector3(x, -0.012 + h * 0.5, z), 0.014, h)
		1:   # 冰原：冰山和一颗星
			_tri(p, Vector3(-0.004, -0.004, z), 0.034, 0.022)
			p.box(Vector3(0.006, 0.006, 0.001), Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0.014, 0.016, z)), COL_DARK)
		2:   # 城市：三栋高楼
			for b: Array in [[-0.012, 0.018], [0.0, 0.03], [0.012, 0.022]]:
				var w := 0.009
				var h: float = b[1]
				p.box(Vector3(w, h, 0.001), Cockpit._at(Vector3(float(b[0]), -0.016 + h * 0.5, z)), COL_DARK)
	return p.build()


static func _tri(p: Cockpit.Parts, center: Vector3, width: float, height: float) -> void:
	var prism := PrismMesh.new()
	prism.size = Vector3(width, height, 0.001)
	p.add(prism, Cockpit._at(center), COL_DARK)
