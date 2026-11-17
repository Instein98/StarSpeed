class_name PaceProfile
extends RefCounted
## 理想车速曲线（开发者 2026-11-16，分层音乐用）：赛道每一米"理论上最快能以多快通过"。
## 经典的两遍扫描：
##   1. 每一米的上限 = 弯道极限车速 sqrt(T-20·g / |κ|) 与 top_speed 中较小的；
##   2. 从前往后：全油门、每个车速都用最合适的档位，能加到多快（不算换挡损失，所以略偏乐观）；
##   3. 从后往前：从这里全力刹车（brake_decel_g），到前面的弯能刚好降到极限车速。
## 刹车区也在曲线里：弯前该刹的时候刹了，比例仍然接近 100%。
## 打滑过弯是超过极限在冒险，不会更快，所以 100% 就是抓地极限；滑着过弯比例会超过 1。
## 只算练习环道和主赛道（出库路在车库附近，不需要）。

const STEP := 1.0      ## 每米一个采样
const KMH := 1.0 / 3.6
const G := 9.8

var _v := {}           ## path_id → PackedFloat32Array（m/s）


func build(track: Track) -> void:
	var loop := _profile(track, Track.PATH_LOOP, true, -1.0)
	_v[Track.PATH_LOOP] = loop
	# 主赛道从环道的岔路口接出来，起点车速取环道在岔路口的理想车速
	var entry := loop[clampi(int(track.fork_s / STEP), 0, loop.size() - 1)]
	_v[Track.PATH_MAIN] = _profile(track, Track.PATH_MAIN, false, entry)


## 车在 (path_id, s) 处的理想车速（m/s）；没有曲线的路段返回 0。
func ideal(path_id: int, s: float) -> float:
	var a: PackedFloat32Array = _v.get(path_id, PackedFloat32Array())
	if a.is_empty():
		return 0.0
	return a[clampi(int(s / STEP), 0, a.size() - 1)]


## 车速 ÷ 理想车速；没有曲线时返回 -1。
func pace(path_id: int, s: float, v: float) -> float:
	var ref := ideal(path_id, s)
	return -1.0 if ref <= 0.0 else v / ref


func _profile(track: Track, path_id: int, cyclic: bool, v_start: float) -> PackedFloat32Array:
	var t := Tuning.d
	var n := int(track.length(path_id) / STEP) + 1
	var cap := PackedFloat32Array()
	cap.resize(n)
	var grade := PackedFloat32Array()
	grade.resize(n)
	var top: float = t.top_speed_kmh * KMH
	for i in n:
		var k := absf(track.curvature_at(path_id, i * STEP))
		cap[i] = top if k < CarSim.KAPPA_EPS else minf(top, sqrt(t.t20_grip_g * G / k))
		grade[i] = track.grade_at(path_id, i * STEP)
	var v := cap.duplicate()
	var dec: float = t.brake_decel_g * G
	# 环道首尾相接：各扫两圈，第二圈接着第一圈结尾的车速，起点处也就受到了上一圈的影响
	var laps := 2 if cyclic else 1
	var cur := 0.0 if cyclic else maxf(v_start, 0.0)
	for lap in laps:
		for i in n:
			cur = minf(cur, cap[i])
			v[i] = cur
			var a := _max_accel(cur, grade[i])
			cur = minf(sqrt(cur * cur + 2.0 * a * STEP), top)
	cur = v[n - 1]
	for lap in laps:
		for i in range(n - 1, -1, -1):
			cur = minf(v[i], cur)
			v[i] = cur
			cur = sqrt(cur * cur + 2.0 * dec * STEP)
	return v


## 车速 v 时全油门最大的加速度：在转速不到断油的档里挑最好的（与 CarSim.step 的算法一致）。
func _max_accel(v: float, grade: float) -> float:
	var t := Tuning.d
	var best := 0.0
	for g in range(1, t.t01_gear_count + 1):
		var rpm := maxf(t.t03_idle_rpm, v / (t.t02_cut_speed_kmh[g - 1] * KMH) * t.t05_cut_rpm)
		if rpm >= t.t05_cut_rpm:
			continue
		best = maxf(best, t.t08_peak_accel[g - 1] * Tuning.curve(t.t07_torque_curve, rpm))
	if grade >= CarSim.GRADE_THRESHOLD:
		best *= t.t16_uphill_factor
	best *= clampf((t.top_speed_kmh * KMH - v) / maxf(t.top_speed_taper_kmh * KMH, 0.01), 0.0, 1.0)
	return best
