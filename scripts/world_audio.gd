class_name WorldAudio
extends Node
## 驾驶中引擎以外的声音（规格 10.3–10.5）：
##   S-14 风声：音量按速度层级表（fx_wind），播放速率 = 0.8 + 车速 ÷ 720 km/h × 0.6。
##   World 总线低通：截止频率 = 20000 − (20000 − 2500) × T-44 的增益，高速时引擎和风声变闷，音乐浮上来。
##   S-04 换挡的机械"咔哒"（升档、降档都有；降档的补油嚎叫由引擎声自己的转速扫动表现）。
##   S-07 回火：6000 转以上松油门、或降档后转速 ≥ 5000 时，1–3 声闷响；两次之间至少 1.5 秒。
##   S-09 掠过声：200 km/h 以上穿过门、拱门、龙门架时一声"呼"。

const WIND_PATH := "res://assets/audio/world/wind.ogg"
const LOWPASS_MAX := 20000.0
const LOWPASS_MIN := 2500.0
const POP_LIFT_RPM := 6000.0
const POP_DOWNSHIFT_RPM := 5000.0
const POP_GAP := 1.5
const POP_SPACING := 0.09
const PASS_MIN_KMH := 200.0
const RUMBLE_PATH := "res://assets/audio/sfx/rumble.wav"
const RUMBLE_DB := -4.0

var main: Node
var car: CarSim
var _wind: AudioStreamPlayer
var _rumble: AudioStreamPlayer
var _lowpass: AudioEffectLowPassFilter
var _last_pop := -10.0
var _time := 0.0
var _pops_left := 0
var _pop_timer := 0.0
var _prev_s := -1.0
var _rng := RandomNumberGenerator.new()


func setup(p_main: Node, p_car: CarSim) -> void:
	main = p_main
	car = p_car
	_rng.seed = 707
	_wind = EngineAudio.make_player(self, EngineAudio.load_stream(WIND_PATH, true), &"Wind")
	_rumble = EngineAudio.make_player(self, EngineAudio.load_stream(RUMBLE_PATH, true), &"SFX")
	var bus := AudioServer.get_bus_index(&"World")
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			_lowpass = AudioServer.get_bus_effect(bus, i)
	car.shift_started.connect(_on_shift)
	# S-08（第 4 轮 #3）：车速上穿 350 km/h 时一次性的"吸进去"轰鸣；回落到 330 以下才能再次触发（T-40，CarSim 里已有回差）
	car.star_speed_changed.connect(func(on: bool) -> void:
		if on and car.mode == CarSim.Mode.DRIVE and main.flow.state in [RunFlow.State.RUN, RunFlow.State.PRACTICE]:
			main.sfx.play("star_warp"))
	car.throttle_changed.connect(_on_throttle)


## 0 – 1：车离护栏有多近（slide_frac 超过 rail_warn_frac 开始，到撞车时为 1）。镜头震动和屏幕边缘红光也用它。
static func rail_warning(c: CarSim) -> float:
	var w := Tuning.d.rail_warn_frac
	return clampf((c.slide_frac - w) / maxf(1.0 - w, 0.01), 0.0, 1.0)


func _process(delta: float) -> void:
	if car == null:
		return
	_time += delta
	var t := Tuning.d
	var v_fx: float = main.camera_rig.v_fx
	var kmh := car.v * 3.6
	var moving := car.mode != CarSim.Mode.LOCKED or kmh > 1.0
	var gain := Tuning.table(t.fx_speed_kmh, t.fx_wind, v_fx) if moving else 0.0
	_wind.volume_db = linear_to_db(gain) if gain > 0.0001 else -80.0
	_wind.pitch_scale = 0.8 + kmh / 720.0 * 0.6
	# 擦护栏预警（第 3 轮 #2）：滑到离护栏不远时，路肩"突突突"，越近越响，车越快越密
	var warn := rail_warning(car)
	_rumble.volume_db = RUMBLE_DB + linear_to_db(warn) if warn > 0.001 and car.mode == CarSim.Mode.DRIVE else -80.0
	_rumble.pitch_scale = clampf(kmh / 250.0, 0.5, 2.5)
	if _lowpass != null:
		var k := smoothstep(t.t44_fade_start_kmh, t.t44_fade_full_kmh, v_fx)
		_lowpass.cutoff_hz = LOWPASS_MAX - (LOWPASS_MAX - LOWPASS_MIN) * k
	# 回火的几声按间隔一声一声放
	if _pops_left > 0:
		_pop_timer -= delta
		if _pop_timer <= 0.0:
			_pops_left -= 1
			_pop_timer = POP_SPACING * _rng.randf_range(0.7, 1.5)
			main.sfx.play("pop", _rng.randf_range(-4.0, 0.0), _rng.randf_range(0.85, 1.2))
	_check_passby(kmh)


func _on_shift(_is_up: bool, _from_gear: int, _to_gear: int) -> void:
	main.sfx.play("shift", -4.0, _rng.randf_range(0.92, 1.08))
	if not _is_up and car.rpm >= POP_DOWNSHIFT_RPM:
		_backfire(1, 2)


func _on_throttle(on: bool) -> void:
	if not on and car.rpm >= POP_LIFT_RPM and car.mode == CarSim.Mode.DRIVE:
		_backfire(1, 3)


func _backfire(lo: int, hi: int) -> void:
	if _time - _last_pop < POP_GAP:
		return
	_last_pop = _time
	_pops_left = _rng.randi_range(lo, hi)
	_pop_timer = 0.05


func _check_passby(kmh: float) -> void:
	if car.path_id != Track.PATH_MAIN or main.scenery == null:
		_prev_s = -1.0
		return
	var s := car.s
	if _prev_s >= 0.0 and s > _prev_s and kmh >= PASS_MIN_KMH:
		for o in main.scenery.overhead_s:
			if _prev_s < o and s >= o:
				main.sfx.play("pass", -2.0, _rng.randf_range(0.9, 1.15))
				break
	_prev_s = s
