class_name StickerDisplay
extends Node3D
## 挡风玻璃内侧右边的三枚奖牌贴纸（规格 5.8）：从上到下森林、冰原、城市。
## 临时替身：扁圆片 + 边圈 + 平的图案剪影，都用引擎自带几何体拼。
## 等级 0 = 没拿过（金黄细虚线圈），1 塑料、2 铜、3 银、4 金。
## 还没做：高光带扫过、金牌的闪光点。
## 盘面和边圈用自发光：贴纸背着座舱的光，按两级明暗会落到暗面，金色压色板后会变成铜色。

const RADIUS := 0.035                 ## 直径 7 cm
const RIM := 0.004
const THICK := 0.002
const POS_TOP := Vector3(0.55, 0.20, -0.58)    ## 相对眼睛，第一枚的位置
const SPACING := 0.085
const POP_TIME := 0.35
const POP_SCALE := 1.8

const COL_DARK := Color("1b2233")
const COL_GOLD := Color("ffc93c")
## 盘面 / 边圈（5.8）
const PLATE := [Color(), Color("4fb8e6"), Color("8a4f22"), Color("8a93a3"), Color("ffc93c")]
const EDGE := [Color(), Color("8a93a3"), Color("c57a3a"), Color("c9d1dc"), Color("f7ecd4")]
const TIER_NAMES := ["", "塑料", "铜", "银", "金"]

var material: Material
var _slots: Array[MeshInstance3D] = []
var _pop: Array[float] = [1.0, 1.0, 1.0]


func setup(p_material: Material, eye: Vector3) -> void:
	material = p_material
	_eye = eye
	for i in 3:
		var m := MeshInstance3D.new()
		m.position = eye + POS_TOP + Vector3(0.0, -SPACING * i, 0.0)
		m.material_override = material
		add_child(m)
		_slots.append(m)


## 换成某个等级；animate = 刚刚拿到，弹一下。
func set_tier(index: int, tier: int, animate := false) -> void:
	_slots[index].mesh = _build(index, tier)
	if animate:
		_pop[index] = 0.0


## 结尾时放大到 1.5 倍，间距按比例放大（以中间那枚为中心）。
var zoom := 1.0
var _eye := Vector3.ZERO


func _process(delta: float) -> void:
	for i in _slots.size():
		if _pop[i] < 1.0:
			_pop[i] = minf(1.0, _pop[i] + delta / POP_TIME)
		var u := _pop[i]
		var k := lerpf(POP_SCALE, 1.0, 1.0 - pow(1.0 - u, 3.0))
		_slots[i].scale = Vector3.ONE * k * zoom
		var center := _eye + POS_TOP + Vector3(0.0, -SPACING, 0.0)
		_slots[i].position = center + Vector3(0.0, -SPACING * (i - 1) * zoom, 0.0)


## 一条高光快速扫过这枚贴纸（9.6：本次等级不高于已有贴纸时；结尾里森林和冰原的贴纸）。
func sweep(_index: int) -> void:
	pass


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
