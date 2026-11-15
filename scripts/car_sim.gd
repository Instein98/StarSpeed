class_name CarSim
extends Node
## R-01 – R-16 的全部模拟；保留最近 T-56 秒的逐帧记录；按给定记录回放（R-21）。
## 不碰任何画面和声音（规格 11.4、11.8）。

@warning_ignore("unused_signal")
signal ignited
signal shift_started(is_up: bool, from_gear: int, to_gear: int)
signal shift_denied
signal limiter_changed(active: bool)
signal shift_lamp_changed(mode: int)
signal throttle_changed(on: bool)
signal tire_zone_changed(zone: int)
signal struggle_changed(active: bool)
signal star_speed_changed(active: bool)
signal failed(kind: int)
signal path_changed(path_id: int)
signal replay_finished
signal exit_armed_changed(on: bool)

enum Mode { DRIVE, LOCKED, COASTING, REPLAY }
enum Zone { QUIET, ONE, TWO, THREE, STRUGGLE }
enum Lamp { OFF, BLINK, BURST }
enum Fail { OFF_TRACK = 1, OVERREV = 2, DOWNSHIFT = 3 }

const G := 9.8
const KMH := 1.0 / 3.6
const GRADE_THRESHOLD := 0.03   ## R-10：±3% 以上才算坡
const KAPPA_EPS := 0.0001       ## R-12
const ZONE_HYSTERESIS := 0.005  ## 5.3：从高分区回低分区要低 0.5 个百分点
const SLIDE_EPS := 0.03          ## 横向位移小于 3 cm 算回到原来的路线
const TIMER_DECAY := 2.0        ## R-09、R-14：计时器每秒回落 2 秒

var track: Track

var mode := Mode.DRIVE
## 为真时每个物理帧从键盘读油门和换挡；测试和回放时关掉，改用 set_throttle / request_shift。
var use_device_input := true

var path_id := 0
var s := 0.0
var v := 0.0                    ## m/s
var gear := 1
var rpm := 0.0
var accel := 0.0                ## 本帧的纵向加速度 m/s²
var throttle := false
var brake := false                ## 刹车踩着（开发者 2026-11-14 加的；规格里没有刹车）

var shifting := false
var shift_is_up := false
var shift_progress := 0.0       ## 0–1，指针扫动用
var shift_rpm_from := 0.0

var limiter_active := false
var lamp_mode := Lamp.OFF
var overrev_timer := 0.0

var kappa := 0.0                ## 已平滑的曲率，左正右负
var grade := 0.0
var v_lim := INF
var ratio := 0.0
var tire_zone := Zone.QUIET
## 打滑的横向位移（米，向右为正）和横向速度。开发者 2026-11-14 的要求：打滑要按真实情况算——
## 车速超过这个弯的极限车速时车真的向弯外侧滑，抓地力够了就能拉回来，滑到路边才算撞。
var lat := 0.0
var lat_vel := 0.0
var slide := 0.0                ## |lat|
var slide_frac := 0.0           ## |lat| ÷ 路边距离，0–1（镜头外甩、晕影用）
var star_speed := false

var exit_armed := false
var from_access := true         ## 车是从出库路并入环道的（影响 R-11 的回看窗口）
var ignition_progress := 0.0

## 最近一次失败的现场：kind、gear、to_gear、rpm、ratio、v。
var last_fail: Dictionary = {}

var _shift_left := 0.0
var _shift_total := 0.0
var _shift_loss_rate := 0.0
var _buffered := 0              ## R-07：+1 升档、−1 降档、0 无
var _record: Array = []
var _replay: Array = []
var _replay_index := 0
var _fail_emitted := false


func _ready() -> void:
	rpm = Tuning.d.t03_idle_rpm


func _physics_process(delta: float) -> void:
	if use_device_input and mode == Mode.DRIVE:
		# 刹车优先：踩着刹车时油门不起作用
		brake = Input.is_action_pressed("brake")
		set_throttle(Input.is_action_pressed("throttle") and not brake)
		var up := Input.is_action_just_pressed("shift_up")
		var down := Input.is_action_just_pressed("shift_down")
		if up != down:   # 4.2：同一帧同时按升档和降档，两个都忽略
			request_shift(up)
	step(delta)


# ───────────────────────── 输入 ─────────────────────────

func set_throttle(on: bool) -> void:
	if on == throttle:
		return
	throttle = on
	throttle_changed.emit(on)


## R-05 / R-06 / R-07。
func request_shift(up: bool) -> void:
	if mode != Mode.DRIVE:
		return
	if shifting:
		_buffered = 1 if up else -1
		return
	var t := Tuning.d
	if up:
		if gear >= t.t01_gear_count:
			shift_denied.emit()
			return
		_begin_shift(true, t.t09_upshift_time, 0.0)
	else:
		if gear <= 1:
			shift_denied.emit()
			return
		var rpm_after := rpm_for(v, gear - 1)   # 按降档前的车速
		if rpm_after > t.t12_blow_rpm:
			_fail(Fail.DOWNSHIFT, {"gear": gear, "to_gear": gear - 1, "rpm": rpm_after})
			return
		var loss: float = t.t58_throttle_downshift_loss if throttle else t.t15_downshift_speed_loss
		_begin_shift(false, t.t10_downshift_time, loss)


func set_exit_armed(on: bool) -> void:
	if on == exit_armed:
		return
	exit_armed = on
	exit_armed_changed.emit(on)


# ───────────────────────── 外部控制（RunDirector / 阶段 1 的 main.gd） ─────────────────────────

## 把车放到指定位置和状态；两个计时器、换挡、缓存、记录全部清零。
func place(p_path: int, p_s: float, p_v: float, p_gear: int, p_from_access := false) -> void:
	var path_was := path_id
	path_id = p_path
	s = p_s
	v = p_v
	gear = p_gear
	brake = false
	from_access = p_from_access or p_path == Track.PATH_ACCESS
	shifting = false
	shift_progress = 0.0
	_buffered = 0
	overrev_timer = 0.0
	_clear_slide()
	accel = 0.0
	_record.clear()
	mode = Mode.DRIVE
	_fail_emitted = false
	rpm = rpm_for(v, gear)
	_update_grip(0.0, false, true)
	_update_engine_flags()
	if path_id != path_was:
		path_changed.emit(path_id)


func get_recording() -> Array:
	return _record.duplicate(true)


## R-21：逐帧照搬记录；播完时发出 replay_finished 并回到 DRIVE。
func start_replay(frames: Array) -> void:
	_replay = frames
	_replay_index = 0
	shifting = false
	_buffered = 0
	overrev_timer = 0.0
	_clear_slide()
	mode = Mode.REPLAY


func rpm_for(speed: float, in_gear: int) -> float:
	var t := Tuning.d
	return maxf(t.t03_idle_rpm, speed / (t.t02_cut_speed_kmh[in_gear - 1] * KMH) * t.t05_cut_rpm)


## 镜头用的里程偏移：最近一个物理帧之后又走出的距离（11.1）。
func render_offset() -> float:
	if mode == Mode.LOCKED:
		return 0.0
	return v * Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second


# ───────────────────────── 每个物理帧 ─────────────────────────

func step(dt: float) -> void:
	_fail_emitted = false
	match mode:
		Mode.LOCKED:
			return
		Mode.COASTING:
			s += v * dt
			return
		Mode.REPLAY:
			_replay_step(dt)
			return
	var t := Tuning.d
	_push_record(dt)

	rpm = rpm_for(v, gear)
	grade = track.grade_at(path_id, s, exit_armed, from_access)
	var a := 0.0
	if shifting:
		var used := minf(dt, _shift_left)
		v = maxf(0.0, v - _shift_loss_rate * used)
		_shift_left -= dt
		shift_progress = clampf(1.0 - _shift_left / _shift_total, 0.0, 1.0)
		if _shift_left <= 0.0:
			shifting = false
			if _buffered != 0:
				var up := _buffered > 0
				_buffered = 0
				request_shift(up)
				if _fail_emitted:
					return
	elif throttle and rpm < t.t05_cut_rpm:
		a = t.t08_peak_accel[gear - 1] * Tuning.curve(t.t07_torque_curve, rpm)   # R-03
		if grade >= GRADE_THRESHOLD:
			a *= t.t16_uphill_factor
		if ratio >= t.t22_zone1_start:
			a *= t.t57_tire_drive_factor                                           # R-03a
	elif throttle:
		a = 0.0                                                                    # R-08 断油
	else:
		a = -_coast_decel(rpm)                                                     # R-04
		if grade <= -GRADE_THRESHOLD:
			a *= t.t17_downhill_factor
	if brake:
		# 刹车：减速度取刹车和松油减速里较大的一个；换挡中也有效
		a = minf(a, -t.brake_decel_g * G)
	accel = a
	v = maxf(0.0, v + a * dt)
	var s_before := s
	s += v * dt
	rpm = rpm_for(v, gear)

	_handle_path_switch(s_before)
	_update_engine_flags()

	# R-09 过转计时器（8 档不计时）
	if gear < t.t01_gear_count and rpm >= t.t05_cut_rpm:
		overrev_timer += dt
		if overrev_timer >= t.t11_overrev_limit:
			_fail(Fail.OVERREV, {"gear": gear, "rpm": rpm})
			return
	else:
		overrev_timer = maxf(0.0, overrev_timer - TIMER_DECAY * dt)

	_update_grip(dt, true, false)
	if _fail_emitted:
		return

	# T-40：只用于 S-08 与 R-45 的判据
	var kmh := v / KMH
	if not star_speed and kmh >= t.t40_star_enter_kmh:
		star_speed = true
		star_speed_changed.emit(true)
	elif star_speed and kmh < t.t40_star_exit_kmh:
		star_speed = false
		star_speed_changed.emit(false)


func _begin_shift(up: bool, duration: float, loss: float) -> void:
	var from := gear
	shift_rpm_from = rpm
	gear += 1 if up else -1
	shifting = true
	shift_is_up = up
	shift_progress = 0.0
	_shift_total = maxf(duration, 0.0001)
	_shift_left = _shift_total
	_shift_loss_rate = v * loss / _shift_total
	rpm = rpm_for(v, gear)
	shift_started.emit(up, from, gear)


## R-04：松油减速度（m/s²）。6000 转及以下取 T-13，到 9000 转线性升到 T-14，再高不再增大。
func _coast_decel(at_rpm: float) -> float:
	var t := Tuning.d
	var r := minf(at_rpm, t.t05_cut_rpm)
	if r <= t.t13_coast_knee_rpm:
		return t.t13_coast_decel_g * G
	var f := (r - t.t13_coast_knee_rpm) / (t.t05_cut_rpm - t.t13_coast_knee_rpm)
	return lerpf(t.t13_coast_decel_g, t.t14_coast_decel_max_g, f) * G


func _handle_path_switch(s_before: float) -> void:
	if path_id == Track.PATH_ACCESS:
		var l := track.length(Track.PATH_ACCESS)
		if s >= l:
			s -= l
			path_id = Track.PATH_LOOP
			from_access = true
			path_changed.emit(path_id)
	elif path_id == Track.PATH_LOOP:
		var l := track.length(Track.PATH_LOOP)
		if exit_armed and s_before < track.fork_s and s >= track.fork_s:
			s -= track.fork_s
			path_id = Track.PATH_MAIN
			from_access = false
			path_changed.emit(path_id)
		elif s >= l:
			s -= l          # R-40：里程循环
			from_access = false
	else:
		s = minf(s, track.length(Track.PATH_MAIN))


func _update_engine_flags() -> void:
	var t := Tuning.d
	var lim := throttle and not shifting and rpm >= t.t05_cut_rpm
	if lim != limiter_active:
		limiter_active = lim
		limiter_changed.emit(lim)
	var lamp := Lamp.OFF
	if rpm >= t.t05_cut_rpm:
		lamp = Lamp.BURST
	elif rpm >= t.t18_shift_lamp_rpm:
		lamp = Lamp.BLINK
	if lamp != lamp_mode:
		lamp_mode = lamp
		shift_lamp_changed.emit(lamp)


## R-11 – R-16。judge = 是否判定失败；snap = 不带回差直接取分区（瞬移后用）。
func _update_grip(dt: float, judge: bool, snap: bool) -> void:
	var t := Tuning.d
	kappa = track.curvature_at(path_id, s, exit_armed, from_access)
	if absf(kappa) < KAPPA_EPS:
		v_lim = INF
		ratio = 0.0
	else:
		v_lim = sqrt(t.t20_grip_g * G / absf(kappa))
		ratio = v / v_lim

	# —— 打滑（替代规格 R-14 / R-15 的"挣扎计时器"和 T-25 的立即失败）——
	# 过这个弯需要的向心加速度是 v²·|κ|，轮胎最多给 T-20·g。
	# 不够（ratio > 1）：差额就是车向弯外侧的加速度。
	# 够了：富余的抓地力先把向外的速度刹住，再把车拉回原来的路线。
	if judge:
		var grip := t.t20_grip_g * G
		var need := v * v * absf(kappa)
		if need > grip:
			lat_vel += signf(kappa) * (need - grip) * dt
		else:
			var target := -lat / maxf(t.slide_return_time, 0.01)
			lat_vel = move_toward(lat_vel, target, (grip - need) * dt)
		lat += lat_vel * dt
		if need <= grip and absf(lat) < SLIDE_EPS and absf(lat_vel) < 0.2:
			lat = 0.0
			lat_vel = 0.0
		slide = absf(lat)
		slide_frac = clampf(slide / t.slide_wall_m, 0.0, 1.0)
		if slide >= t.slide_wall_m:
			_fail(Fail.OFF_TRACK, {"gear": gear, "ratio": ratio, "v": v})
			return

	var zone := tire_zone
	var thresholds: Array[float] = [t.t22_zone1_start, t.t23_zone2_start, t.t24_zone3_start]
	if ratio >= 1.0:
		zone = Zone.STRUGGLE        # 抓地力不够，正在向外滑。抓地力一恢复就不算打滑了，即使车还在往原路线回
	else:
		var z := 0
		if snap:
			pass
		elif tire_zone == Zone.STRUGGLE:
			z = Zone.THREE          # R-16：救回后立即切到第三段
		else:
			z = tire_zone
		while z < 3 and ratio >= thresholds[z]:
			z += 1
		while z > 0 and ratio < thresholds[z - 1] - (0.0 if snap else ZONE_HYSTERESIS):
			z -= 1
		zone = z as Zone

	var struggling := zone == Zone.STRUGGLE
	if zone != tire_zone:
		var was_struggling := tire_zone == Zone.STRUGGLE
		tire_zone = zone
		tire_zone_changed.emit(zone)
		if struggling != was_struggling:
			struggle_changed.emit(struggling)


func _clear_slide() -> void:
	lat = 0.0
	lat_vel = 0.0
	slide = 0.0
	slide_frac = 0.0


func _fail(kind: int, info: Dictionary) -> void:
	info["kind"] = kind
	last_fail = info
	_fail_emitted = true
	failed.emit(kind)


# ───────────────────────── R-21a 记录与 R-21 回放 ─────────────────────────

func _push_record(dt: float) -> void:
	_record.push_back([path_id, s, v, gear, throttle, exit_armed, from_access])
	var keep := int(ceil(Tuning.d.t56_replay_time / dt))
	while _record.size() > keep:
		_record.pop_front()


func _replay_step(dt: float) -> void:
	if _replay_index >= _replay.size():
		mode = Mode.DRIVE
		replay_finished.emit()
		return
	var f: Array = _replay[_replay_index]
	_replay_index += 1
	var path_was := path_id
	path_id = f[0]
	s = f[1]
	v = f[2]
	var gear_was := gear
	gear = f[3]
	set_throttle(f[4])
	set_exit_armed(f[5])
	from_access = f[6]
	rpm = rpm_for(v, gear)
	if gear != gear_was:
		shift_started.emit(gear > gear_was, gear_was, gear)
	if path_id != path_was:
		path_changed.emit(path_id)
	_update_engine_flags()
	_update_grip(dt, false, false)
	_clear_slide()
	if _replay_index >= _replay.size():
		mode = Mode.DRIVE
		replay_finished.emit()
