extends SceneTree
# 阶段 1 自动检查（不属于项目文件）。运行：godot --headless --path <项目> -s <本文件>

const DT := 1.0 / 120.0
const KMH := 1.0 / 3.6
var T
var track
var car
var fails: Array = []
var ok_count := 0
var bad_count := 0


func check(name: String, cond: bool, detail := "") -> void:
	if cond:
		ok_count += 1
		print("  [通过] ", name, "  ", detail)
	else:
		bad_count += 1
		print("  [失败] ", name, "  ", detail)


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
	for c in car.failed.get_connections():
		car.failed.disconnect(c["callable"])
	car.failed.connect(func(k): fails.append(k))

	print("== 赛道几何 ==")
	var lt: Transform3D = track.transform_at(1, track.length(1))
	check("环道全长 1629", absf(track.length(1) - 1629.0) < 3.0, "%.1f" % track.length(1))
	check("环道闭合回 (0,300)", lt.origin.distance_to(Vector3(0, 0, -300)) < 0.05, str(lt.origin))
	check("岔路口里程 400", absf(track.fork_s - 400.0) < 0.01)
	# 2026-11-15 按"8 档 8500 转 = 680 km/h、每个区段只有一处能到极速"重新定的长度
	# （规格原值是 5378 / 11885 / 17527 / 18127）
	var exp := [0.0, 6607.5, 13326.8, 20257.5]
	for i in 4:
		check("区段线 %d" % i, absf(track.section_start[i] - exp[i]) < 3.0, "%.1f" % track.section_start[i])
	check("主赛道含尾段全长", absf(track.length(2) - 20857.5) < 3.0, "%.1f" % track.length(2))
	var min_h := 1e9
	var max_h := -1e9
	var s := 0.0
	while s < track.length(2):
		var h: float = track.transform_at(2, s).origin.y
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
		s += 5.0
	check("高度处处 ≥ 0", min_h > -0.01, "最低 %.2f 最高 %.2f" % [min_h, max_h])
	check("终点高度回到 0 附近", absf(track.transform_at(2, track.length(2)).origin.y) < 0.5, "%.2f" % track.transform_at(2, track.length(2)).origin.y)
	# 6.2：主赛道自己不相交（里程差 200 m 以上的两点相距 ≥ 56 m）
	var pts: Array = []
	s = 0.0
	while s < track.length(2):
		pts.append(track.transform_at(2, s).origin)
		s += 10.0
	var min_d := 1e9
	for i in pts.size():
		for j in range(i + 20, pts.size()):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[j]
			var d := Vector2(a.x - b.x, a.z - b.z).length()
			if d < min_d:
				min_d = d
	var min_loop := 1e9
	var ls := 0.0
	while ls < track.length(1):
		var q: Vector3 = track.transform_at(1, ls).origin
		for i in range(40, pts.size()):
			var a2: Vector3 = pts[i]
			min_loop = minf(min_loop, Vector2(a2.x - q.x, a2.z - q.z).length())
		ls += 10.0
	check("主赛道（岔路口 400 m 之后）不碰环道", min_loop >= 50.0, "最近 %.1f m" % min_loop)
	check("主赛道不自交（≥ 56 m）", min_d >= 50.0, "最近 %.1f m（10 m 采样）" % min_d)
	check("并入口曲率：来自出库路 = 0", absf(track.curvature_at(1, 1.0, false, true)) < 1e-6)
	check("并入口曲率：绕圈过来 ≠ 0", absf(track.curvature_at(1, 1.0, false, false)) > 0.005)

	print("== 加速 ==")
	# 无限直道：用主赛道 F18 的数据不够长，直接算公式
	var t_total := _zero_to_limiter()
	check("0 → 8 档断油约 22 秒（T-08 手感目标）", absf(t_total - 22.0) < 2.0, "%.2f 秒" % t_total)

	print("== 首次出库（全油门，7800 升档）==")
	fails.clear()
	car.place(0, 0.0, 0.0, 1, true)
	car.set_throttle(true)
	var merged_v := 0.0
	for n in 2000:
		if car.rpm >= T.t06_best_shift_rpm and not car.shifting:
			car.request_shift(true)
		var was: int = car.path_id
		car.step(DT)
		if was == 0 and car.path_id == 1:
			merged_v = car.v / KMH
		if car.path_id == 1 and car.s > 60.0:
			break
		if not fails.is_empty():
			break
	check("并入环道时不判失败", fails.is_empty(), "并入时 %d km/h" % roundi(merged_v))

	print("== 三种失败 ==")
	fails.clear()
	car.place(1, 10.0, 80.0 * KMH, 2, true)
	car.set_throttle(true)
	var tt := 0.0
	while fails.is_empty() and tt < 10.0:
		car.step(DT)
		tt += DT
		if car.rpm >= T.t05_cut_rpm and car.gear == 2 and absf(car.v / KMH - 110.0) > 0.5:
			pass
	check("失败 2：2 档顶红线", fails == [2], "从 80 km/h 起 %.2f 秒后；断油车速 %.1f km/h" % [tt, car.v / KMH])
	fails.clear()
	car.place(1, 10.0, 160.0 * KMH, 3, true)
	car.set_throttle(false)
	car.request_shift(false)
	check("失败 3：降档过转", fails == [3], str(car.last_fail))
	fails.clear()
	car.place(1, 10.0, 100.0 * KMH, 3, true)
	car.request_shift(false)
	for n in 30:
		car.step(DT)
	check("合法降档：3→2，掉速约 6%", fails.is_empty() and car.gear == 2, "降档后 %.1f km/h" % (car.v / KMH))
	fails.clear()
	car.place(1, 1100.0, 230.0 * KMH, 5, false)   # L3 回程直道，冲向 L4（极限 138）
	car.set_throttle(true)
	tt = 0.0
	while fails.is_empty() and tt < 20.0:
		car.step(DT)
		tt += DT
	check("失败 1：超速进急弯，滑到路边", fails == [1] and absf(car.lat) >= T.slide_wall_m, "ratio %.3f 于 %s，外滑 %.1f m" % [car.last_fail.get("ratio", 0.0), track.segment_label_at(car.path_id, car.s), car.lat])
	# 救车：略超极限进弯，开始外滑后踩刹车，应该拉回原路线、不失败
	fails.clear()
	car.place(1, 1100.0, 150.0 * KMH, 4, false)
	car.set_throttle(false)
	var max_lat := 0.0
	var slid := false
	tt = 0.0
	while fails.is_empty() and tt < 12.0:
		# 车停住就回不了线（回线的横向速度 ≤ 车速 × tan(最大回线角)），所以刹到 80 km/h 就松开
		car.brake = car.slide > 0.5 and car.v > 80.0 * KMH
		car.set_throttle(slid and car.v < 70.0 * KMH)
		if car.brake:
			slid = true
		# 保持略超极限的车速直到开始滑
		if not slid:
			car.v = 150.0 * KMH
		car.step(DT)
		max_lat = maxf(max_lat, absf(car.lat))
		tt += DT
	car.brake = false
	check("救车：外滑后刹车能拉回来", fails.is_empty() and slid and car.slide == 0.0, "最大外滑 %.2f m，结束时 %.2f m，车速 %d km/h" % [max_lat, car.lat, roundi(car.v / KMH)])

	print("== 换挡规则 ==")
	fails.clear()
	car.place(2, 100.0, 30.0 * KMH, 1)
	var denied := [0]
	car.shift_denied.connect(func(): denied[0] += 1)
	car.request_shift(false)
	check("1 档降档被拒绝", denied[0] == 1 and car.gear == 1)
	car.place(2, 100.0, 300.0 * KMH, 8)
	car.request_shift(true)
	check("8 档升档被拒绝", denied[0] == 2 and car.gear == 8)
	car.place(2, 100.0, 100.0 * KMH, 3)
	car.request_shift(true)
	car.request_shift(true)   # 换挡中再按：缓存 1 次
	for n in 60:
		car.step(DT)
	check("R-07 缓存一次换挡", car.gear == 5, "档位 %d" % car.gear)
	# 8 档到极速（8500 转）：不断油、不爆缸，车速停在 top_speed
	fails.clear()
	car.place(2, 3000.0, 640.0 * KMH, 8)
	car.set_throttle(true)
	var lim9 := false
	for n in 1200:
		car.step(DT)
		lim9 = lim9 or car.limiter_active
		if car.path_id != 2 or not fails.is_empty():
			break
	check("8 档极速：不断油、不爆缸", fails.is_empty() and not lim9 and car.v / KMH <= T.top_speed_kmh + 0.5 and car.v / KMH > T.top_speed_kmh - 15.0,
			"%.0f km/h，%d 转" % [car.v / KMH, car.rpm])

	print("== 环道绕圈（保守驾驶 3 圈）==")
	fails.clear()
	car.place(1, 0.0, 60.0 * KMH, 2, false)
	var laps := 0
	var prev_s := 0.0
	for n in 120 * 200:
		car.set_throttle(car.v < 100.0 * KMH)
		prev_s = car.s
		car.step(DT)
		if car.s < prev_s:
			laps += 1
			if laps >= 3:
				break
	check("环道能一直绕圈", laps >= 3 and fails.is_empty() and car.path_id == 1, "圈数 %d" % laps)
	# 驶出开关
	car.set_exit_armed(true)
	for n in 120 * 60:
		car.set_throttle(car.v < 100.0 * KMH)
		car.step(DT)
		if car.path_id == 2:
			break
	check("驶出开关打开后经岔路口进主赛道", car.path_id == 2 and car.s < 5.0, "s = %.2f" % car.s)
	car.set_exit_armed(false)

	print("== 模拟驾驶员跑三个区段（R-47 / 参考用时）==")
	for sec in 3:
		_drive_section(sec)

	print("\n结果：%d 通过，%d 失败" % [ok_count, bad_count])
	quit(0 if bad_count == 0 else 1)


func _zero_to_limiter() -> float:
	var v := 0.0
	var gear := 1
	var t := 0.0
	var pause := 0.0
	while t < 60.0:
		var rpm: float = car.rpm_for(v, gear)
		if pause > 0.0:
			pause -= DT
		elif gear < 8 and rpm >= T.t06_best_shift_rpm:
			gear += 1
			pause = T.t09_upshift_time
		elif rpm >= T.t05_cut_rpm:
			return t
		else:
			v += T.t08_peak_accel[gear - 1] * root.get_node("Tuning").curve(T.t07_torque_curve, rpm) * DT
		t += DT
	return t


# 简单的模拟驾驶员：按 0.95 × 极限速度做目标，反向推刹车点（只算松油 0.6 g × 0.85 的余量），
# 7800 升档；松油时只要降档后转速 ≤ 8600 就降档。
func _drive_section(sec: int) -> void:
	var s0: float = track.section_start[sec]
	var s1: float = track.section_start[sec + 1]
	var n := int(s1 - s0) + 400
	var cap := PackedFloat32Array()
	cap.resize(n)
	for i in n:
		var k: float = absf(track.curvature_at(2, s0 + i))
		cap[i] = 1e9 if k < 1e-4 else 0.95 * sqrt(T.t20_grip_g * 9.8 / k)
	var dec: float = T.t13_coast_decel_g * 9.8 * 0.85 * T.t17_downhill_factor / 0.7 * 0.7
	for i in range(n - 2, -1, -1):
		cap[i] = minf(cap[i], sqrt(cap[i + 1] * cap[i + 1] + 2.0 * dec))
	fails.clear()
	var v0: float = [200.0, 450.0, 220.0][sec] * KMH
	var g0: int = [4, 7, 5][sec]
	car.place(2, s0, v0, g0)
	var t := 0.0
	var vmax := 0.0
	var limiter8 := false
	var max_ratio := 0.0
	while car.s < s1 and t < 300.0 and fails.is_empty():
		var i := clampi(int(car.s - s0) + 1, 0, n - 1)
		var want: bool = car.v < cap[i]
		car.set_throttle(want)
		if not car.shifting:
			if want and car.rpm >= T.t06_best_shift_rpm and car.gear < 8:
				car.request_shift(true)
			elif not want and car.gear > 1 and car.rpm_for(car.v, car.gear - 1) <= 8600.0:
				car.request_shift(false)
			elif want and car.gear > 1 and car.rpm < 5000.0 and car.rpm_for(car.v, car.gear - 1) <= 7600.0:
				car.request_shift(false)
		car.step(DT)
		t += DT
		vmax = maxf(vmax, car.v)
		max_ratio = maxf(max_ratio, car.ratio)
		if car.gear == 8 and car.limiter_active:
			limiter8 = true
	var name: String = track.section_names[sec]
	check("%s：跑完且无失败" % name, fails.is_empty() and car.s >= s1,
			"用时 %.1f 秒，最高 %d km/h，最大 ratio %.3f%s" % [t, roundi(vmax / KMH), max_ratio,
			"" if fails.is_empty() else "，失败 %s 于 %s" % [str(car.last_fail), track.segment_label_at(2, car.s)]])
	check("%s：8 档没到断油（R-47）" % name, not limiter8)
	check("%s：最高车速 ≥ 350 km/h（R-45）" % name, vmax / KMH >= 350.0)
