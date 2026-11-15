extends Node
## 自动加载 `Tuning`：读取 data/tuning.tres，提供按 ID 取值和折线查表（规格 11.4、7.2）。

signal reloaded

const PATH := "res://data/tuning.tres"

var d: TuningData


func _ready() -> void:
	d = load(PATH) as TuningData
	assert(d != null, "无法读取 " + PATH)


## F2：只在编辑器版本里重新读取（导出后的版本无效）。
func reload() -> bool:
	if not OS.has_feature("editor"):
		return false
	var fresh := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as TuningData
	if fresh == null:
		push_warning("调参文件重新读取失败: " + PATH)
		return false
	d = fresh
	reloaded.emit()
	return true


## 按规格里的 ID 取值，例如 get_by_id("T-05")。一个 ID 对应多个字段时返回第一个。
func get_by_id(id: String) -> Variant:
	var prefix := id.to_lower().replace("-", "") + "_"
	if prefix.length() == 3:  # "t5_" → "t05_"
		prefix = "t0" + prefix.substr(1)
	for p: Dictionary in d.get_property_list():
		var n: String = p["name"]
		if n.begins_with(prefix):
			return d.get(n)
	return null


## 折线查表：points 为 (x, y) 序列，x 递增；两端之外取端点值。
static func curve(points: PackedVector2Array, x: float) -> float:
	var n := points.size()
	if n == 0:
		return 0.0
	if x <= points[0].x:
		return points[0].y
	for i in range(1, n):
		if x <= points[i].x:
			var a := points[i - 1]
			var b := points[i]
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return points[n - 1].y


## 两列表查表（速度层级表用）：xs 递增，在相邻点之间线性插值。
static func table(xs: PackedFloat32Array, ys: PackedFloat32Array, x: float) -> float:
	var n := mini(xs.size(), ys.size())
	if n == 0:
		return 0.0
	if x <= xs[0]:
		return ys[0]
	for i in range(1, n):
		if x <= xs[i]:
			return lerpf(ys[i - 1], ys[i], (x - xs[i - 1]) / (xs[i] - xs[i - 1]))
	return ys[n - 1]
