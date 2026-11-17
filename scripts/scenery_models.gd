class_name SceneryModels
extends RefCounted
## 区段景物的临时模型：用代码按规格 8.4 的描述拼出来（没有 Blender 模型，开发者要求先用替身）。
## 原点在底面中心，正面朝 −Z。颜色只取规格 8.2 的色值。
## 以后有真模型时，替换这里的函数返回值即可，摆放（scenery.gd）不用改。

const COL_DARK := Color("1b2233")
const COL_RED := Color("ef4a2f")
const COL_GOLD := Color("ffc93c")
const COL_WARM := Color("f7ecd4")
const COL_ROAD := Color("4a5262")
const COL_ROAD_DARK := Color("363d4b")
# 森林
const COL_FOREST := Color("2f9e6a")
const COL_FOREST_DARK := Color("23805a")
const COL_TRUNK := Color("8a6a4a")
const COL_TRUNK_DARK := Color("5e4733")
const COL_MOUNTAIN := Color("6f9fc0")
# 冰原
const COL_SNOW := Color("f4fbff")
const COL_SNOW_SHADE := Color("d5eaf5")
const COL_ICE := Color("a5dcf2")
const COL_DEEP_ICE := Color("2e7fb0")
# 城市
const COL_BLD_GREY := Color("8a93a3")
const COL_BLD_NAVY := Color("2b3550")
const COL_BLD_WARM := Color("d9cdb4")
const COL_GLASS := Color("4fb8e6")
## 楼体四种颜色（A-40：朱红、深蓝黑、楼灰、楼暖白）
const BUILDING_COLORS: Array[Color] = [Color("ef4a2f"), Color("1b2233"), Color("8a93a3"), Color("d9cdb4")]
const BUILDING_HEIGHTS: Array[float] = [45.0, 80.0, 150.0]


static func _night(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.25)


static func _glow(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.0)


## A-20 松树：高 9 / 14 m，六边形树干向上收细，4–6 层下沿锯齿的不规则锥，几根枯枝。
static func pine(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2001 + variant
	var h := 9.0 if variant == 0 else 14.0
	var k := MeshKit.new()
	var trunk_top := h * 0.45
	var low := MeshKit.ring(Vector3.ZERO, h * 0.035, 6)
	var high := MeshKit.ring(Vector3(0, trunk_top, 0), h * 0.018, 6)
	k.band(low, high, COL_TRUNK)
	# 根部的隆起
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var d := Vector3(cos(a), 0, sin(a))
		k.cone(PackedVector3Array([d * h * 0.03 + d.cross(Vector3.UP) * 0.15, d * h * 0.09, d * h * 0.03 - d.cross(Vector3.UP) * 0.15]),
				Vector3(0, h * 0.07, 0) + d * h * 0.02, COL_TRUNK_DARK)
	# 枯枝短桩
	for i in 2 + variant:
		var a := rng.randf() * TAU
		var y := rng.randf_range(0.12, 0.25) * h
		k.beam(Vector3(0, y, 0), Vector3(cos(a) * h * 0.08, y + h * 0.02, sin(a) * h * 0.08), h * 0.012, COL_TRUNK_DARK)
	var layers := 4 if variant == 0 else 6
	var base_y := h * 0.18
	var base_r := h * 0.22
	for i in layers:
		var u := float(i) / layers
		var r := base_r * (1.0 - u * 0.75)
		var y0 := base_y + (h * 0.78 - base_y) * u
		var top := y0 + h * 0.30 * (1.0 - u * 0.4)
		if i == layers - 1:
			top = h
		var n := 7 + (i % 3)
		var pts := PackedVector3Array()
		var phase := rng.randf() * TAU
		for j in n:
			var a := phase + TAU * j / n
			var rr := r * rng.randf_range(0.85, 1.1)
			var yy := y0 - (h * 0.04 if j % 2 == 0 else 0.0)   # 下沿一高一低，呈锯齿
			pts.append(Vector3(cos(a) * rr, yy, sin(a) * rr))
		var col := COL_FOREST if i % 2 == 0 else COL_FOREST_DARK
		k.cone(pts, Vector3(0, top, 0), col, true, COL_FOREST_DARK)
	return k.build()


## A-22 岩石：不规则多面体，底部埋进地面。
static func rock() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2101
	var k := MeshKit.new()
	var n := 7
	var low := PackedVector3Array()
	var mid := PackedVector3Array()
	for i in n:
		var a := TAU * i / n + rng.randf() * 0.3
		low.append(Vector3(cos(a), -0.3, sin(a)) * Vector3(rng.randf_range(1.1, 1.5), 1.0, rng.randf_range(1.0, 1.4)))
		mid.append(Vector3(cos(a + 0.4) * rng.randf_range(0.8, 1.1), rng.randf_range(0.7, 1.1), sin(a + 0.4) * rng.randf_range(0.7, 1.0)))
	k.band(low, mid, COL_ROAD)
	k.cone(mid, Vector3(rng.randf_range(-0.2, 0.2), 1.6, rng.randf_range(-0.2, 0.2)), COL_ROAD)
	return k.build()


## A-30 冰山：高 25 / 50 m，底宽为高度的 80%，尖锐多面体，1–2 个次峰，底部一圈深冰色。
static func iceberg(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3001 + variant
	var h := 25.0 if variant == 0 else 50.0
	var k := MeshKit.new()
	var peaks := [[Vector3.ZERO, 1.0]]
	for i in 1 + variant:
		var a := rng.randf() * TAU
		peaks.append([Vector3(cos(a), 0, sin(a)) * h * 0.3, rng.randf_range(0.45, 0.65)])
	for pk: Array in peaks:
		var c: Vector3 = pk[0]
		var ph: float = h * float(pk[1])
		var r := ph * 0.4
		var n := 6
		var base := PackedVector3Array()
		var foot := PackedVector3Array()
		var mid := PackedVector3Array()
		for j in n:
			var a := TAU * j / n + rng.randf() * 0.4
			var rr := r * rng.randf_range(0.8, 1.15)
			foot.append(c + Vector3(cos(a) * rr * 1.05, -0.5, sin(a) * rr * 1.05))
			base.append(c + Vector3(cos(a) * rr, ph * 0.06, sin(a) * rr))
			mid.append(c + Vector3(cos(a + 0.3) * rr * 0.55, ph * rng.randf_range(0.4, 0.55), sin(a + 0.3) * rr * 0.55))
		k.band(foot, base, COL_DEEP_ICE)
		k.band(base, mid, COL_SNOW)
		k.cone(mid, c + Vector3(rng.randf_range(-0.1, 0.1) * r, ph, rng.randf_range(-0.1, 0.1) * r), COL_SNOW)
	return k.build()


## A-31 冰锥：高 4 m，3–5 根倾斜的尖棱柱成簇。
static func ice_spikes() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3101
	var k := MeshKit.new()
	for i in 4:
		var a := TAU * i / 4.0 + rng.randf() * 0.5
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.3, 0.9)
		var hh := rng.randf_range(2.2, 4.0)
		var tilt := off.normalized() * hh * rng.randf_range(0.15, 0.35)
		var base := MeshKit.ring(off + Vector3(0, -0.2, 0), rng.randf_range(0.25, 0.4), 4, rng.randf() * TAU)
		k.cone(base, off + tilt + Vector3(0, hh, 0), COL_ICE if i % 2 == 0 else COL_SNOW_SHADE)
	return k.build()


## A-33 冰拱门：跨度 16 m、高 9 m，不对称的冰拱，顶部垂下 3–5 根冰棱。横跨方向沿 X。
static func ice_arch() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3201
	var k := MeshKit.new()
	var seg := 12
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	for i in seg + 1:
		var u := float(i) / seg
		var a := PI * u
		# 不对称：左腿粗、右腿细；顶部偏右一点
		var x := -cos(a) * 8.0
		var y := sin(a) * 9.0 * (1.0 + 0.08 * sin(a * 2.0))
		var thick := lerpf(2.4, 1.2, u)
		var center := Vector3(x, y, 0)
		var normal := Vector3(-cos(a), sin(a), 0).normalized()
		var p_in := center - normal * thick * 0.3
		var p_out := center + normal * thick * 0.7
		if i == 0:
			p_in = Vector3(-8.0 + 1.0, -0.2, 0)
			p_out = Vector3(-8.0 - 1.4, -0.2, 0)
		elif i == seg:
			p_in = Vector3(8.0 - 0.6, -0.2, 0)
			p_out = Vector3(8.0 + 0.8, -0.2, 0)
		if i > 0:
			var d := Vector3(0, 0, 1.2)
			var col := COL_ICE if i % 2 == 0 else COL_SNOW_SHADE
			k.quad(prev_in - d, p_in - d, p_out - d, prev_out - d, col)
			k.quad(prev_in + d, prev_out + d, p_out + d, p_in + d, col)
			k.quad(prev_out - d, p_out - d, p_out + d, prev_out + d, COL_SNOW)
			k.quad(prev_in - d, prev_in + d, p_in + d, p_in - d, COL_ICE)
		prev_in = p_in
		prev_out = p_out
	# 冰棱：从拱顶内沿垂下来
	for i in 4:
		var u := rng.randf_range(0.3, 0.7)
		var a := PI * u
		var x := -cos(a) * 8.0
		var y := sin(a) * 9.0 * (1.0 + 0.08 * sin(a * 2.0)) - 0.7
		var root := MeshKit.ring(Vector3(x, y, rng.randf_range(-0.6, 0.6)), 0.25, 4)
		k.cone(root, Vector3(x, y - rng.randf_range(1.2, 2.2), root[0].z), COL_ICE)
	return k.build()


## A-24 森林门：跨度 14 m、高 8 m，两根粗原木立柱加横梁，横梁上挂金黄色木牌。横跨方向沿 X。
static func forest_gate() -> ArrayMesh:
	var k := MeshKit.new()
	for side: float in [-1.0, 1.0]:
		k.band(MeshKit.ring(Vector3(side * 7.5, 0, 0), 0.55, 6), MeshKit.ring(Vector3(side * 7.5, 8.6, 0), 0.45, 6), COL_TRUNK)
	k.beam(Vector3(-8.6, 7.9, 0), Vector3(8.6, 7.9, 0), 0.8, COL_TRUNK_DARK)
	k.beam(Vector3(-8.2, 6.9, 0), Vector3(8.2, 6.9, 0), 0.4, COL_TRUNK)
	k.box(Vector3(0, 6.0, 0), Vector3(5.0, 1.4, 0.2), COL_GOLD)
	return k.build()


## A-40 楼房：变体 0/1/2 = 45/80/150 m，平顶带水箱 / 带天线 / 尖顶；分底座、楼身、楼顶三段；
## 每 4 m 一排凹进去的窗格（夜间自发光）。body 是楼体颜色。临街面朝 −Z。
static func building(variant: int, body: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4001 + variant
	var h: float = BUILDING_HEIGHTS[variant]
	var w: float = [18.0, 20.0, 22.0][variant]
	var d: float = [18.0, 22.0, 24.0][variant]
	var k := MeshKit.new()
	var podium := 6.0
	k.box(Vector3(0, podium * 0.5, 0), Vector3(w + 2.0, podium, d + 2.0), COL_BLD_NAVY if body != COL_BLD_NAVY else COL_BLD_GREY)
	var top_h := h * 0.06
	k.box(Vector3(0, podium + (h - podium - top_h) * 0.5, 0), Vector3(w, h - podium - top_h, d), body)
	k.box(Vector3(0, h - top_h * 0.5, 0), Vector3(w - 2.0, top_h, d - 2.0), body.darkened(0.15) if body != COL_DARK else COL_BLD_NAVY)
	# 窗格：四个立面每 4 m 一排横条，贴在墙面外 5 cm（替身里用"贴上去的深色条"表示凹进去）
	var win := _night(COL_BLD_NAVY if body != COL_BLD_NAVY else COL_GLASS)
	var y := podium + 2.0
	while y < h - top_h - 2.0:
		for face in 4:
			var yaw := PI * 0.5 * face
			var half_span: float = (w if face % 2 == 0 else d) * 0.5 - 1.5
			var out: float = (d if face % 2 == 0 else w) * 0.5 + 0.05
			var b := Basis(Vector3.UP, yaw)
			var a := b * Vector3(-half_span, y, -out)
			var c := b * Vector3(half_span, y, -out)
			k.quad(a, c, c + Vector3(0, 1.6, 0), a + Vector3(0, 1.6, 0), win)
		y += 4.0
	match variant:
		0:   # 水箱
			k.band(MeshKit.ring(Vector3(3, h, 2), 2.0, 8), MeshKit.ring(Vector3(3, h + 4.0, 2), 2.0, 8), COL_BLD_GREY)
			k.cone(MeshKit.ring(Vector3(3, h + 4.0, 2), 2.0, 8), Vector3(3, h + 5.0, 2), COL_BLD_GREY)
		1:   # 天线
			k.beam(Vector3(0, h, 0), Vector3(0, h + 18.0, 0), 0.6, COL_BLD_GREY)
			k.box(Vector3(0, h + 18.3, 0), Vector3(0.8, 0.6, 0.8), _glow(COL_RED))
		2:   # 尖顶
			k.cone(MeshKit.ring(Vector3(0, h, 0), (w - 2.0) * 0.5, 4, PI * 0.25), Vector3(0, h + 30.0, 0), body.lightened(0.1))
	return k.build()


## A-43 龙门架：跨度 14 m、高 8 m，桁架结构。finish = 朱红涂装的终点龙门架（字牌在 scenery.gd 里另加）。
static func gantry(finish: bool) -> ArrayMesh:
	var col := COL_RED if finish else COL_BLD_GREY
	var k := MeshKit.new()
	for side: float in [-1.0, 1.0]:
		var x := side * 8.0
		for dz: float in [-0.6, 0.6]:
			k.beam(Vector3(x, 0, dz), Vector3(x, 8.6, dz), 0.3, col)
		var y := 0.0
		while y < 8.0:
			k.beam(Vector3(x, y, -0.6), Vector3(x, y + 1.4, 0.6), 0.15, col)
			y += 1.4
	for dy: float in [7.2, 8.6]:
		for dz: float in [-0.6, 0.6]:
			k.beam(Vector3(-8.0, dy, dz), Vector3(8.0, dy, dz), 0.3, col)
	var x2 := -8.0
	while x2 < 8.0:
		k.beam(Vector3(x2, 7.2, 0), Vector3(x2 + 1.6, 8.6, 0), 0.15, col)
		x2 += 1.6
	return k.build()


## A-44 高架桥墩：2 × 2 m，高 1 m（摆放时按路面高度纵向缩放）。
static func pier() -> ArrayMesh:
	var k := MeshKit.new()
	k.box(Vector3(0, 0.5, 0), Vector3(2, 1, 2), COL_BLD_GREY)
	return k.build()


## A-50 护栏段：长 4 m、高 0.8 m，朱红 / 暖白两种。沿 −Z 方向排。
static func guardrail(white: bool) -> ArrayMesh:
	var k := MeshKit.new()
	k.box(Vector3(0, 0.4, 0), Vector3(0.3, 0.8, 4.0), COL_WARM if white else COL_RED)
	return k.build()


## A-51 弯道箭头牌：2 × 2 m，离地 1 m，深蓝黑底，金黄色折线箭头；left = 指向左。牌面朝 +Z（朝来车）。
static func arrow_sign(left: bool) -> ArrayMesh:
	var k := MeshKit.new()
	k.beam(Vector3(0, 0, 0), Vector3(0, 1.0, 0), 0.15, COL_BLD_GREY)
	k.box(Vector3(0, 2.0, 0), Vector3(2.0, 2.0, 0.12), COL_DARK)
	var s := -1.0 if left else 1.0
	var z := 0.07
	for off: float in [-0.35, 0.35]:
		var tip := Vector3(s * (0.55 + off), 2.0, z)
		var tail_top := Vector3(-s * 0.15 + s * off, 2.6, z)
		var tail_bot := Vector3(-s * 0.15 + s * off, 1.4, z)
		var w := Vector3(-s * 0.3, 0, 0)
		k.quad(tail_top, tip, tip + w, tail_top + w, COL_GOLD)
		k.quad(tip, tail_bot, tail_bot + w, tip + w, COL_GOLD)
	return k.build()


## 车库（A-10 内部）和基地外观（A-11），规格 6.3。坐标就是世界坐标（车库里车的位置是原点，车头朝北 = −Z）。
## 规格的平面坐标 (x, y) 对应 Godot (x, −y)。
static func base() -> ArrayMesh:
	var k := MeshKit.new()
	# —— 外观：东西 40、南北 30、高 10，x −20..20，y −16..14（z −14..16）——
	var wall := COL_DARK
	var zn := -14.0
	var zs := 16.0
	k.box(Vector3(-12.0, 5.0, zn), Vector3(16.0, 10.0, 0.4), wall)        # 北墙左半
	k.box(Vector3(12.0, 5.0, zn), Vector3(16.0, 10.0, 0.4), wall)         # 北墙右半
	k.box(Vector3(0.0, 7.5, zn), Vector3(8.0, 5.0, 0.4), wall)            # 大门上方
	k.box(Vector3(0.0, 5.0, zs), Vector3(40.0, 10.0, 0.4), wall)          # 南墙
	k.box(Vector3(-20.0, 5.0, 1.0), Vector3(0.4, 10.0, 30.0), wall)       # 西墙
	k.box(Vector3(20.0, 5.0, 1.0), Vector3(0.4, 10.0, 30.0), wall)        # 东墙
	k.box(Vector3(0.0, 10.0, 1.0), Vector3(40.4, 0.4, 30.4), COL_BLD_NAVY)  # 平顶
	# 朱红屋檐线
	k.box(Vector3(0.0, 9.6, zn - 0.25), Vector3(40.6, 0.5, 0.1), COL_RED)
	k.box(Vector3(0.0, 9.6, zs + 0.25), Vector3(40.6, 0.5, 0.1), COL_RED)
	k.box(Vector3(-20.25, 9.6, 1.0), Vector3(0.1, 0.5, 30.6), COL_RED)
	k.box(Vector3(20.25, 9.6, 1.0), Vector3(0.1, 0.5, 30.6), COL_RED)
	# —— 车库内部：宽 14、长 24、高 6，x −7..7，y −10..14（z −14..10）——
	k.box(Vector3(0.0, 0.0, -2.0), Vector3(14.0, 0.04, 24.0), COL_ROAD)            # 地面
	k.box(Vector3(-7.0, 3.0, -2.0), Vector3(0.2, 6.0, 24.0), COL_DARK)             # 西墙
	k.box(Vector3(7.0, 3.0, -2.0), Vector3(0.2, 6.0, 24.0), COL_DARK)              # 东墙
	k.box(Vector3(0.0, 3.0, 10.0), Vector3(14.0, 6.0, 0.2), COL_DARK)              # 后墙
	k.box(Vector3(0.0, 6.0, -2.0), Vector3(14.0, 0.2, 24.0), COL_BLD_NAVY)         # 顶
	k.box(Vector3(-5.5, 5.5, zn + 0.15), Vector3(3.0, 1.0, 0.1), COL_DARK)         # 门内两侧的墙垛
	k.box(Vector3(5.5, 5.5, zn + 0.15), Vector3(3.0, 1.0, 0.1), COL_DARK)
	# 两条金黄引导线（相距 3 m），从车两侧通向大门
	for x: float in [-1.5, 1.5]:
		k.box(Vector3(x, 0.03, -7.0), Vector3(0.15, 0.02, 14.0), COL_GOLD)
	# 三排暖白灯带（自发光）
	for x: float in [-4.0, 0.0, 4.0]:
		k.box(Vector3(x, 5.88, -2.0), Vector3(0.5, 0.06, 20.0), _glow(COL_WARM))
	# 东西墙边各 4 个朱红工具柜（2 × 0.8 × 1.8）
	for side: float in [-1.0, 1.0]:
		for i in 4:
			k.box(Vector3(side * 6.5, 0.9, 6.0 - i * 2.4), Vector3(0.8, 1.8, 2.0), COL_RED)
	# 西墙上金黄色字牌底板 6 × 1.2，中心离地 3.5（字在 scenery.gd 里另加）
	k.box(Vector3(-6.85, 3.5, 2.0), Vector3(0.06, 1.2, 6.0), COL_GOLD)
	return k.build()
