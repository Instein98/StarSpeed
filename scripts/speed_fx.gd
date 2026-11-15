class_name SpeedFx
extends MeshInstance3D
## 挂在 WorldPost 上：按速度层级表设置世界后处理着色器的参数（规格 7.3、8.5 V-02 / V-03 / V-04、11.4）。
## 只看车速，不看档位，没有"进入星速"的开关。

const VANISH_DISTANCE := 200.0      ## 消失点 = 赛道前方 200 m 处在屏幕上的投影
const VANISH_LIMIT := Vector2(0.4, 0.2)   ## 限制在屏幕中心左右各 40% 宽、上下各 20% 高之内
const FLOW_REF_SPEED := 200.0       ## 线化图案流速 = 车速 ÷ 200 m/s × 3 个画面半高 / 秒
const FLOW_RATE := 3.0
const FLOW_WRAP := 64.0

var car: CarSim
var track: Track

var v_fx := 0.0                     ## 平滑车速（km/h，T-41）
var _flow := 0.0
var _vanish := Vector2(0.5, 0.5)


func bind(p_car: CarSim, p_track: Track) -> void:
	car = p_car
	track = p_track


func _process(delta: float) -> void:
	if car == null:
		return
	var mat := get_surface_override_material(0) as ShaderMaterial
	if mat == null:
		return
	var t := Tuning.d
	var kmh := car.v / CarSim.KMH
	v_fx += (kmh - v_fx) * (1.0 - exp(-delta / maxf(t.t41_vfx_smooth_time, 0.001)))
	mat.set_shader_parameter("streak", Tuning.table(t.fx_speed_kmh, t.fx_streak, v_fx))
	mat.set_shader_parameter("clear_radius", Tuning.table(t.fx_speed_kmh, t.fx_clear_radius, v_fx))
	mat.set_shader_parameter("line_strength", Tuning.table(t.fx_speed_kmh, t.fx_line, v_fx))
	mat.set_shader_parameter("mode_b", t.t48_fx_mode == "B")
	var motion := t.t48_fx_mode == "M"
	mat.set_shader_parameter("motion_mode", motion)
	# 用平滑后的车速，换挡掉速时拉线长度不会跳；随车速按幂曲线增长，中低速接近没有
	var grow := pow(clampf(v_fx / maxf(t.fx_motion_full_kmh, 1.0), 0.0, 1.0), t.fx_motion_power)
	mat.set_shader_parameter("motion_dist", v_fx * CarSim.KMH * t.fx_motion_exposure * grow)
	mat.set_shader_parameter("motion_max", t.fx_motion_max_span)

	# 线化图案沿半径向外流动，用脚本累加的"游戏时间"驱动，暂停时冻结
	_flow = fposmod(_flow + car.v / FLOW_REF_SPEED * FLOW_RATE * delta, FLOW_WRAP)
	mat.set_shader_parameter("line_flow", _flow)

	var cam := get_parent() as Camera3D
	if cam == null:
		return
	var size := Vector2(cam.get_viewport().get_visible_rect().size)
	if motion:
		# 方案 M：拉线的中心是车此刻真正前进的方向（赛道切线），不提前偏向前方的弯
		var here := track.advance(car.path_id, car.s, car.render_offset(), car.exit_armed, car.from_access)
		var heading := -track.transform_at(here[0], here[1]).basis.z
		var far_point := cam.global_position + heading * 1000.0
		if not cam.is_position_behind(far_point):
			_vanish = cam.unproject_position(far_point) / size
	else:
		# 方案 A / B（规格 V-02）：消失点跟着前方 200 m 的路移动
		var loc := track.advance(car.path_id, car.s, car.render_offset() + VANISH_DISTANCE, car.exit_armed, car.from_access)
		var point := track.transform_at(loc[0], loc[1]).origin
		if not cam.is_position_behind(point):
			var uv := cam.unproject_position(point) / size
			_vanish = Vector2(
					clampf(uv.x, 0.5 - VANISH_LIMIT.x, 0.5 + VANISH_LIMIT.x),
					clampf(uv.y, 0.5 - VANISH_LIMIT.y, 0.5 + VANISH_LIMIT.y))
	mat.set_shader_parameter("vanish_uv", _vanish)
