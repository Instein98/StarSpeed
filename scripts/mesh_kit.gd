class_name MeshKit
extends RefCounted
## 用代码拼低多边形模型的小工具：三角形、四边形、方块、棱锥、棱台。
## 只用顶点色（规格 8.1、8.3），平直着色由两级明暗材质按屏幕导数求法线，所以顶点不需要共享。
## 顶点色 alpha：1 普通，0 自发光，0.25 夜间自发光（规格 8.3 第 1 条）。

var verts := PackedVector3Array()
var colors := PackedColorArray()


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	verts.append(a); verts.append(b); verts.append(c)
	colors.append(col); colors.append(col); colors.append(col)


## a-b-c-d 按顺序绕一圈的四边形。
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(a, b, c, col)
	tri(a, c, d, col)


## 中心 center、尺寸 size 的方块，可选绕竖轴转 yaw。
func box(center: Vector3, size: Vector3, col: Color, yaw := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	var p: Array[Vector3] = []
	for k in 8:
		var c := Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z)
		p.append(center + b * c)
	quad(p[0], p[1], p[3], p[2], col)   # −Z
	quad(p[4], p[6], p[7], p[5], col)   # +Z
	quad(p[0], p[2], p[6], p[4], col)   # −X
	quad(p[1], p[5], p[7], p[3], col)   # +X
	quad(p[2], p[3], p[7], p[6], col)   # +Y
	quad(p[0], p[4], p[5], p[1], col)   # −Y


## 两点之间的方形截面杆（桁架、冰棱用）。
func beam(a: Vector3, b: Vector3, thick: float, col: Color) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 1e-4:
		return
	var f := dir / len
	var up := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(f, up)
	var h := thick * 0.5
	var corners: Array[Vector3] = [Vector3(-h, -h, 0), Vector3(h, -h, 0), Vector3(h, h, 0), Vector3(-h, h, 0)]
	var ra: Array[Vector3] = []
	var rb: Array[Vector3] = []
	for c in corners:
		ra.append(a + basis * c)
		rb.append(b + basis * c)
	for i in 4:
		var j := (i + 1) % 4
		quad(ra[i], ra[j], rb[j], rb[i], col)
	quad(ra[0], ra[1], ra[2], ra[3], col)
	quad(rb[0], rb[3], rb[2], rb[1], col)


## 一圈 n 个底点（ring）连到一个顶点 apex 的棱锥侧面；cap = 是否封底。
func cone(ring: PackedVector3Array, apex: Vector3, col: Color, cap := false, cap_col := Color()) -> void:
	var n := ring.size()
	for i in n:
		tri(ring[i], ring[(i + 1) % n], apex, col)
	if cap:
		var c := Vector3.ZERO
		for p in ring:
			c += p
		c /= n
		for i in n:
			tri(ring[(i + 1) % n], ring[i], c, cap_col)


## 两圈点数相同的环之间的侧面（棱台、树干）。
func band(lower: PackedVector3Array, upper: PackedVector3Array, col: Color) -> void:
	var n := lower.size()
	for i in n:
		var j := (i + 1) % n
		quad(lower[i], lower[j], upper[j], upper[i], col)


## 水平的正 n 边形一圈点：中心 center、半径 r、起始角 phase。
static func ring(center: Vector3, r: float, n: int, phase := 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var a := phase + TAU * i / n
		out.append(center + Vector3(cos(a) * r, 0.0, sin(a) * r))
	return out


func build() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
