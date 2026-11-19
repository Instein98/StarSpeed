class_name CameraRig
extends Node3D
## 第 4.3 节两台摄像机的位置、朝向、视野、震动（规格 4.3、7.3、11.2a、11.4）。
## 失败 1 的飞出运动（7.3）：镜头离开赛道，沿切线以当时的车速直飞，同时以 60°/秒 向弯外侧翻滚；
## 座舱摄像机取同样的翻滚角，看起来是整台车在翻。

const EYE_HEIGHT := 1.05            ## 路面上方 1.05 m
const LOOK_AHEAD := 8.0             ## 水平朝向取 s + 8 m 处的切线
const MOTION_SMOOTH := 0.15         ## 后仰、侧倾的平滑时间常数
const HEAD_SMOOTH := 0.1            ## 转头限速之后再加的平滑
const NOD_TIME := 0.25              ## 降档前点 / 带油降档后仰的时长
const ACCEL_REF := 14.0             ## 后仰角 = 加速度 ÷ 14 m/s² × T-33
const THROTTLE_DOWNSHIFT_TILT_DEG := 2.0   ## 7.3：带油降档后仰 2°
const COCKPIT_PITCH_SHARE := 0.5    ## 座舱摄像机取后仰 / 前点角度的 50%
const STRUGGLE_RETURN_TIME := 0.3   ## 救回后 0.3 秒内回正
## 转向不足的转头，座舱只取 40%：取满的话会转出临时座舱外壳的边缘，露出后面的世界
const UNDERSTEER_COCKPIT_SHARE := 0.4
const MM := 0.001
const FLY_ROLL_DEG_PER_SEC := 60.0

var car: CarSim
var track: Track
var cockpit_camera: Camera3D
## 结尾镜头（0 = 平常，1 = 抬向贴纸），已经过缓动曲线
var ending_look := 0.0
const ENDING_YAW_DEG := 28.0
const ENDING_PITCH_DEG := 12.0
const ENDING_FOV := 40.0

## 速度层级用的平滑车速（km/h，时间常数 T-41）
var v_fx := 0.0
## 当前震动幅度（毫米），供调试用
var shake_mm := 0.0

var _fov_world := 70.0
var _fov_cockpit := 70.0
var _pulse := 0.0
var _pitch := 0.0          # 度，正 = 后仰
var _roll := 0.0           # 度，正 = 向右倾
var _nod_time := 1.0
var _nod_amp := 0.0        # 度，正 = 前点
var _head_limited := 0.0   # 度，正 = 向左转头
var _head := 0.0
var _swing := 0.0          # 度，挣扎外甩的幅度
var _swing_dir := 0.0
var _return_yaw := 0.0     # 度，救回途中车头朝原路线偏的角度（正 = 向左）
var _understeer := 0.0     # −1 – 1，正 = 左弯的转向不足
var _shake_from := Vector2.ZERO
var _shake_to := Vector2.ZERO
var _roll_from := 0.0
var _roll_to := 0.0
var _shake_phase := 0.0
var _rng := RandomNumberGenerator.new()
var _tangent := Vector3.FORWARD
var _flying := false
var _fly_pos := Vector3.ZERO
var _fly_basis := Basis.IDENTITY
var _fly_vel := Vector3.ZERO
var _fly_roll := 0.0
var _fly_dir := 1.0

@onready var world_camera: Camera3D = $WorldCamera


func bind(p_car: CarSim, p_track: Track, p_cockpit_camera: Camera3D) -> void:
	car = p_car
	track = p_track
	cockpit_camera = p_cockpit_camera
	car.shift_started.connect(_on_shift_started)
	_fov_world = Tuning.curve(Tuning.d.t30_world_fov_curve, 0.0)
	_fov_cockpit = Tuning.curve(Tuning.d.t47_cockpit_fov_curve, 0.0)


func _on_shift_started(is_up: bool, _from: int, _to: int) -> void:
	var t := Tuning.d
	if is_up:
		_pulse = t.t32_fov_pulse_deg                      # T-32
	else:
		_nod_time = 0.0
		_nod_amp = -THROTTLE_DOWNSHIFT_TILT_DEG if car.throttle else t.t34_pitch_nod_deg


## 失败 1：从此刻的镜头位置沿赛道切线飞出去。
func start_flyoff() -> void:
	_flying = true
	_fly_pos = world_camera.global_position
	_fly_basis = world_camera.global_transform.basis
	_fly_vel = _tangent * car.v
	_fly_roll = 0.0
	# 左弯（κ > 0）时弯外侧是右边：向右翻滚
	_fly_dir = 1.0 if car.kappa >= 0.0 else -1.0


func stop_flyoff() -> void:
	_flying = false
	_swing = 0.0


func _process(delta: float) -> void:
	if car == null:
		return
	if _flying:
		_fly_pos += _fly_vel * delta
		_fly_roll += FLY_ROLL_DEG_PER_SEC * delta
		var roll := Basis(Vector3.BACK, deg_to_rad(-_fly_roll * _fly_dir))
		world_camera.global_transform = Transform3D(_fly_basis * roll, _fly_pos)
		if cockpit_camera != null:
			cockpit_camera.transform = Transform3D(roll, Cockpit.EYE)
		return
	var t := Tuning.d
	var kmh := car.v / CarSim.KMH
	v_fx += (kmh - v_fx) * _k(delta, t.t41_vfx_smooth_time)

	# —— 基础位置与朝向 ——
	var off := car.render_offset()
	var here := track.advance(car.path_id, car.s, off, car.exit_armed, car.from_access)
	var ahead := track.advance(car.path_id, car.s, off + LOOK_AHEAD, car.exit_armed, car.from_access)
	var xf := track.transform_at(here[0], here[1])
	var fwd_pitch := -xf.basis.z
	_tangent = fwd_pitch
	var fwd_yaw := -track.transform_at(ahead[0], ahead[1]).basis.z
	var flat := Vector3(fwd_yaw.x, 0.0, fwd_yaw.z).normalized()
	var dir := (flat * sqrt(maxf(1.0 - fwd_pitch.y * fwd_pitch.y, 0.0001)) + Vector3.UP * fwd_pitch.y).normalized()
	var base := Basis.looking_at(dir, Vector3.UP)
	# 打滑的横向位移（向右为正）
	var outward := track.right_at(here[0], here[1]) * car.lat
	var eye := xf.origin + Vector3.UP * EYE_HEIGHT + outward

	# —— 视野（T-30、T-47、T-31、T-32）——
	var k_fov := _k(delta, t.t31_fov_smooth_time)
	# 画面效果强度（设置）：视野随车速变宽的幅度按倍数缩小
	var fxs := SaveData.fx_scale()
	var fw0 := Tuning.curve(t.t30_world_fov_curve, 0.0)
	var fc0 := Tuning.curve(t.t47_cockpit_fov_curve, 0.0)
	_fov_world += (fw0 + (Tuning.curve(t.t30_world_fov_curve, kmh) - fw0) * fxs - _fov_world) * k_fov
	_fov_cockpit += (fc0 + (Tuning.curve(t.t47_cockpit_fov_curve, kmh) - fc0) * fxs - _fov_cockpit) * k_fov
	if t.t32_fov_pulse_time > 0.0:
		_pulse = maxf(0.0, _pulse - t.t32_fov_pulse_deg / t.t32_fov_pulse_time * delta)

	# —— 后仰 / 前点（T-33、T-34）——
	var k_motion := _k(delta, MOTION_SMOOTH)
	_pitch += (clampf(car.accel / ACCEL_REF, -1.0, 1.0) * t.t33_pitch_back_deg - _pitch) * k_motion
	var nod := 0.0
	if _nod_time < NOD_TIME:
		nod = _nod_amp * sin(PI * _nod_time / NOD_TIME)
		_nod_time += delta

	# —— 侧倾（T-35）：向弯外侧倾 ——
	_roll += (minf(1.0, car.ratio) * t.t35_roll_deg * signf(car.kappa) - _roll) * k_motion

	# —— 转头看弯（T-36、T-39、T-39a）——
	var head_target := 0.0
	var arc := track.next_arc(car.path_id, car.s, car.exit_armed)
	if arc["found"] and float(arc["entry_dist"]) <= t.t39_head_turn_dist_m:
		var target: Vector3 = arc["apex"] if float(arc["apex_dist"]) > 0.0 else arc["exit"]
		var local := base.inverse() * (target + Vector3.UP * EYE_HEIGHT - eye)
		if Vector2(local.x, local.z).length() > 2.0:
			head_target = clampf(rad_to_deg(atan2(-local.x, -local.z)), -t.t36_head_turn_max_deg, t.t36_head_turn_max_deg)
	_head_limited = move_toward(_head_limited, head_target, t.t39a_head_turn_speed_deg * delta)
	_head += (_head_limited - _head) * _k(delta, HEAD_SMOOTH)

	var struggling := car.tire_zone == CarSim.Zone.STRUGGLE
	# —— 转向不足的视角（开发者 2026-11-14：不要抖动，用头的偏转和倾斜来表示）——
	# 这个游戏里的失控只有一种：进弯太快、车头不肯拐（转向不足）。驾驶员会把头转向、歪向弯内侧。
	# 程度 u：接近极限（ratio 从 T-22 到 100%）时 0 → understeer_edge_share，是"快到边缘了"的暗示；
	# 抓地力不够（ratio ≥ 100%）时随超出的多少和已经滑出去的距离升到 1。
	# 抓地力一恢复（ratio < 100%）u 就退回去，即使车还在往原路线回。
	var u := 0.0
	if car.ratio >= 1.0:
		var over := clampf((car.ratio - 1.0) / maxf(t.understeer_full_over, 0.001), 0.0, 1.0)
		u = lerpf(t.understeer_edge_share, 1.0, maxf(over, car.slide_frac))
	else:
		u = t.understeer_edge_share * clampf(inverse_lerp(t.t22_zone1_start, 1.0, car.ratio), 0.0, 1.0)
	_understeer += (u * signf(car.kappa) - _understeer) * _k(delta, t.understeer_smooth_time)
	_swing = absf(_understeer) * t.t38_struggle_yaw_deg
	_swing_dir = signf(_understeer)         # 左弯（κ > 0）向左看，即正的偏航
	# 救回来往原路线开时，车头是朝着原路线偏的（不是整台车横着平移回去）：
	# 车头方向 = 赛道方向再转 atan(横向速度 ÷ 车速)。只在往回开的时候算；向外滑时车头并没有指向外侧。
	var heading_target := 0.0
	if car.lat * car.lat_vel < 0.0 and car.v > 1.0:
		heading_target = -rad_to_deg(atan2(car.lat_vel, car.v)) * t.slide_return_yaw_gain
	_return_yaw += (heading_target - _return_yaw) * _k(delta, t.understeer_smooth_time)
	var lean := -_understeer * t.understeer_roll_deg   # 左弯头向左歪（_roll 的正方向是向右）

	# —— 震动（T-37，7.3）：各来源取最大值，不相加；上下、左右各自独立的随机噪声 ——
	var amp := Tuning.table(t.fx_speed_kmh, t.fx_shake_mm, v_fx) * SaveData.fx_scale()
	if car.tire_zone == CarSim.Zone.TWO:
		amp = maxf(amp, t.t37_zone2_mm)
	elif car.tire_zone == CarSim.Zone.THREE:
		amp = maxf(amp, t.t37_zone3_mm)
	if car.limiter_active:
		amp = maxf(amp, t.t37_limiter_mm)
	var world_amp := t.t37_limiter_mm if car.limiter_active else 0.0
	var roll_jitter_amp := 0.0
	if struggling:
		amp = maxf(amp, t.t37_struggle_mm)
		world_amp = t.t37_struggle_mm
		roll_jitter_amp = t.t37_struggle_roll_deg
	# 擦护栏预警：离护栏越近震得越厉害（第 3 轮 #2）
	var warn := WorldAudio.rail_warning(car)
	if warn > 0.0:
		amp = maxf(amp, t.rail_warn_shake_mm * warn * SaveData.fx_scale())
		world_amp = maxf(world_amp, t.rail_warn_shake_mm * 0.5 * warn * SaveData.fx_scale())
	shake_mm = amp
	_shake_phase += delta * t.t37_freq_hz
	while _shake_phase >= 1.0:
		_shake_phase -= 1.0
		_shake_from = _shake_to
		_shake_to = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
		_roll_from = _roll_to
		_roll_to = _rng.randf_range(-1.0, 1.0)
	var noise := _shake_from.lerp(_shake_to, _shake_phase)
	var roll_jitter := lerpf(_roll_from, _roll_to, _shake_phase) * roll_jitter_amp

	# —— 世界摄像机 ——
	var yaw := deg_to_rad(_head + _swing * _swing_dir + _return_yaw)
	var world_basis := base * Basis(Vector3.UP, yaw) \
			* Basis(Vector3.RIGHT, deg_to_rad(_pitch - nod)) \
			* Basis(Vector3.BACK, deg_to_rad(-(_roll + lean) + roll_jitter))
	var world_shake := (world_basis.x * noise.x + world_basis.y * noise.y) * world_amp * MM
	world_camera.global_transform = Transform3D(world_basis, eye + world_shake)
	world_camera.fov = clampf(_fov_world + _pulse, 1.0, 179.0)

	# —— 座舱摄像机：转头 100%、后仰 / 前点 50%、震动位移；不取侧倾 ——
	if cockpit_camera != null:
		var cockpit_basis := Basis(Vector3.UP, deg_to_rad(_head + _swing * _swing_dir * UNDERSTEER_COCKPIT_SHARE)) \
				* Basis(Vector3.RIGHT, deg_to_rad((_pitch - nod) * COCKPIT_PITCH_SHARE)) \
				* Basis(Vector3.BACK, deg_to_rad(-lean))   # 转向不足是头的动作，座舱也跟着歪
		var cockpit_shake := Vector3(noise.x, noise.y, 0.0) * amp * MM
		# 结尾（6.7 第 3 步）：座舱摄像机向右转 28°、向上抬 12°，视野收到 40°，让贴纸占画面右半部
		if ending_look > 0.0:
			cockpit_basis = cockpit_basis * Basis(Vector3.UP, deg_to_rad(-ENDING_YAW_DEG * ending_look)) \
					* Basis(Vector3.RIGHT, deg_to_rad(ENDING_PITCH_DEG * ending_look))
		cockpit_camera.transform = Transform3D(cockpit_basis, Cockpit.EYE + cockpit_shake)
		cockpit_camera.fov = lerpf(_fov_cockpit, ENDING_FOV, ending_look)


static func _k(delta: float, time_constant: float) -> float:
	if time_constant <= 0.0:
		return 1.0
	return 1.0 - exp(-delta / time_constant)
