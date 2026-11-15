extends SceneTree
## 赛道设计用的模拟：一个会用刹车的熟练驾驶员从主赛道起点一路开到终点，
## 统计每个区段的用时、最高车速、"极速"（接近 top_speed）出现了几次、每次多久，
## 以及车速达到 7 档高转（7 档 8000 转对应的车速）以上的次数。
## 用法：Godot --headless --path . --script tools/track_design.gd

const DT := 1.0 / 120.0
const KMH := 1.0 / 3.6
const BRAKE_USE := 0.85          # 驾驶员用到刹车能力的多少
const LIMIT_USE := 0.97          # 过弯用到极限车速的多少
const TOP_BAND := 0.985          # 车速 ≥ 极速的 98.5% 算"在极速上"

var car
var track
var T


func _initialize() -> void:
	await process_frame
	T = root.get_node("Tuning").d
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	track = scene.get_node("WorldViewport/Track")
	car = scene.get_node("CarSim")
	car.use_device_input = false
	car.set_physics_process(false)
	scene.set_physics_process(false)
	var fails := []
	for c in car.failed.get_connections():
		car.failed.disconnect(c["callable"])
	car.failed.connect(func(k): fails.append(k))

	var total: float = track.length(2)
	var n := int(total) + 2
	var cap := PackedFloat32Array()
	cap.resize(n)
	for i in n:
		var k: float = absf(track.curvature_at(2, float(i)))
		cap[i] = 1e9 if k < 1e-4 else LIMIT_USE * sqrt(T.t20_grip_g * 9.8 / k)
	var dec: float = T.brake_decel_g * 9.8 * BRAKE_USE
	for i in range(n - 2, -1, -1):
		cap[i] = minf(cap[i], sqrt(cap[i + 1] * cap[i + 1] + 2.0 * dec))

	var top: float = T.top_speed_kmh * KMH
	var v7: float = T.t02_cut_speed_kmh[6] * KMH * 8000.0 / T.t05_cut_rpm
	car.place(2, 0.0, 120.0 * KMH, 3)
	var sec := 0
	var t := 0.0
	var sec_t0 := 0.0
	var vmax := 0.0
	var top_runs: Array = []      # [时长, 段名]
	var top_t := 0.0
	var high_runs := 0
	var in_high := false
	var high_labels: Array = []
	while car.s < total - 1.0 and t < 2000.0 and fails.is_empty():
		var i := clampi(int(car.s) + 1, 0, n - 1)
		var want: bool = car.v < cap[i]
		car.brake = car.v > cap[i] * 1.002
		car.set_throttle(want and not car.brake)
		if not car.shifting:
			if want and car.rpm >= T.t06_best_shift_rpm and car.gear < T.t01_gear_count:
				car.request_shift(true)
			elif car.gear > 1 and car.rpm_for(car.v, car.gear - 1) <= 7600.0 and (car.brake or car.rpm < 5200.0):
				car.request_shift(false)
		car.step(DT)
		t += DT
		vmax = maxf(vmax, car.v)
		if car.v >= top * TOP_BAND:
			top_t += DT
		elif top_t > 0.0:
			top_runs.append("%.1f 秒@%s" % [top_t, track.segment_label_at(2, car.s)])
			top_t = 0.0
		if car.v >= v7 and not in_high:
			in_high = true
			high_runs += 1
			high_labels.append(track.segment_label_at(2, car.s))
		elif car.v < v7 * 0.95:
			in_high = false
		if sec < 3 and car.s >= track.section_start[sec + 1]:
			if top_t > 0.0:
				top_runs.append("%.1f 秒@%s(跨区段)" % [top_t, track.segment_label_at(2, car.s)])
				top_t = 0.0
			print("%s: 长 %.0f m，用时 %.1f 秒，最高 %d km/h | 极速 %d 次 %s | ≥%d km/h（7 档高转）%d 次 %s" % [
					track.section_names[sec], track.section_start[sec + 1] - track.section_start[sec], t - sec_t0,
					roundi(vmax / KMH), top_runs.size(), str(top_runs), roundi(v7 / KMH), high_runs, str(high_labels)])
			sec += 1
			sec_t0 = t
			vmax = 0.0
			top_runs = []
			high_runs = 1 if in_high else 0
			high_labels = [track.segment_label_at(2, car.s)] if in_high else []
	if not fails.is_empty():
		print("失败：", car.last_fail, " 于 ", track.segment_label_at(2, car.s))
	quit(0)
