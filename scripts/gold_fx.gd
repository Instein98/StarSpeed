class_name GoldFx
extends MeshInstance3D
## 金牌版环境的天穹氛围物（规格 6.6、A-62）：
##   meteor：每 1.5 秒一颗流星，出现在车头前方左右各 60° 之内、仰角 25°–55°，向右下方 30° 划过 20°，历时 0.8 秒；
##           本体 0.6° 宽的暖白亮线，后面拖一条 8° 长、渐细的流星尾（#9fd6ee）。
##   aurora：三条竖直的帘幕状极光带，下沿仰角 20°、上沿 45°，各水平跨 90°，中心在区段起点车头方向的 −50°、0°、+50°；
##           自下而上由极光绿过渡到极光紫，沿水平方向振幅 4°、周期 8 秒的波浪摆动。
## 都是自发光的网格，挂在跟着摄像机走的天穹节点下，半径 3700 m（在雾的截止距离之外）。

const RADIUS := 3700.0
const METEOR_EVERY := 1.5
const METEOR_TIME := 0.8
const METEOR_TRAVEL_DEG := 20.0
const METEOR_WIDTH_DEG := 0.6
const METEOR_TAIL_DEG := 8.0
const COL_HEAD := Color(0.969, 0.925, 0.831, 0.0)
const COL_TAIL := Color(0.624, 0.839, 0.933, 0.0)
## 规格是仰角 20°–45°；但驾驶视角里画面上沿只到仰角 25° 左右，按规格只看得见一条绿色的底边，
## 所以放低到 8°–30°（见 QUESTIONS.md）
const AURORA_LOW := 10.0
const AURORA_HIGH := 24.0
const AURORA_SPAN := 90.0
const AURORA_WAVE_DEG := 4.0
const AURORA_PERIOD := 8.0
const AURORA_OFFSETS: Array[float] = [-50.0, 0.0, 50.0]
const COL_GREEN := Color(0.239, 0.863, 0.592, 0.0)
const COL_PURPLE := Color(0.651, 0.42, 1.0, 0.0)

var kind := ""
var heading_deg := 0.0      ## 区段起点线处的车头方向（极光的方位以它为准）
var _time := 0.0
var _next_meteor := 0.3
var _meteors: Array = []    ## [起点方位, 起点仰角, 已过时间]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 6601
	extra_cull_margin = 16384.0


static func _dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	var k := MeshKit.new()
	if kind == "meteor":
		_update_meteors(delta, k)
	elif kind == "aurora":
		_build_aurora(k)
	mesh = k.build()


func _update_meteors(delta: float, k: MeshKit) -> void:
	_next_meteor -= delta
	if _next_meteor <= 0.0:
		_next_meteor = METEOR_EVERY
		var cam := get_viewport().get_camera_3d()
		var fwd := -cam.global_transform.basis.z if cam != null else Vector3.FORWARD
		var cam_az := rad_to_deg(atan2(fwd.x, -fwd.z))
		_meteors.append([cam_az + _rng.randf_range(-60.0, 60.0), _rng.randf_range(25.0, 55.0), 0.0])
	var keep: Array = []
	var down := deg_to_rad(30.0)
	for m: Array in _meteors:
		m[2] = float(m[2]) + delta
		var u := float(m[2]) / METEOR_TIME
		if u >= 1.0:
			continue
		keep.append(m)
		var travel := METEOR_TRAVEL_DEG * u
		var head_az := float(m[0]) + cos(down) * travel
		var head_el := float(m[1]) - sin(down) * travel
		# 尾巴沿反方向拖 8°（刚出现时尾巴还没长全），由宽变细
		var tail := minf(METEOR_TAIL_DEG, travel + 1.0)
		var segs := 8
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in segs + 1:
			var f := float(i) / segs
			var az := head_az - cos(down) * tail * f
			var el := head_el + sin(down) * tail * f
			var w := METEOR_WIDTH_DEG * (1.0 - f) * 0.5
			# 垂直于运动方向的偏移（在方位 / 仰角平面里）
			var l := _dir(az - sin(down) * w, el - cos(down) * w) * RADIUS
			var r := _dir(az + sin(down) * w, el + cos(down) * w) * RADIUS
			if i > 0:
				var col := COL_HEAD if i <= 1 else COL_TAIL
				k.quad(prev_l, prev_r, r, l, col)
			prev_l = l
			prev_r = r
	_meteors = keep


func _build_aurora(k: MeshKit) -> void:
	var cols := 48
	var col_mid := COL_GREEN.lerp(COL_PURPLE, 0.5)
	col_mid.a = 0.0
	for b in AURORA_OFFSETS.size():
		var center := heading_deg + AURORA_OFFSETS[b]
		var prev: Array[Vector3] = []
		for i in cols + 1:
			var u := float(i) / cols
			var wave := AURORA_WAVE_DEG * sin(TAU * (_time / AURORA_PERIOD + u * 1.5 + b * 0.33))
			var az := center + (u - 0.5) * AURORA_SPAN + wave
			# 帘幕的上沿也跟着起伏一点
			var top := AURORA_HIGH + 2.0 * sin(TAU * (u * 2.0 + _time / AURORA_PERIOD * 0.5 + b))
			var pts: Array[Vector3] = []
			for r in 4:
				pts.append(_dir(az, lerpf(AURORA_LOW, top, r / 3.0)) * RADIUS)
			# 帘幕：一条条竖的光带，中间留缝（每 3 列空 1 列）
			if i % 2 == 1:
				var row_cols: Array[Color] = [COL_GREEN, col_mid, COL_PURPLE]
				for r in 3:
					k.quad(prev[r], pts[r], pts[r + 1], prev[r + 1], row_cols[r])
			prev = pts
