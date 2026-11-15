class_name TireAudio
extends Node
## 轮胎声，三个状态（开发者 2026-11-14 第三次反馈）：
##   刚碰到极限（ratio 从 T-22 到 T-23）：轻的吱吱声；
##   处于极限中（ratio 从 T-23 到 100%）：更响、更尖的尖叫，警示作用；
##   打滑（车已经向外滑，CarSim.Zone.STRUGGLE）：粗糙的滑动摩擦声。
## 相邻状态 30 毫秒交叉。规则上的分区（R-13）不变。

const DIR := "res://assets/audio/tires/"
const FILES: Array[String] = ["squeal_light.ogg", "squeal_hard.ogg", "struggle.ogg"]

var car: CarSim
var mix: Dictionary = {}

var _players: Array[AudioStreamPlayer] = []
var _fade: Array[float] = [0.0, 0.0, 0.0]


func _ready() -> void:
	mix = EngineAudio.load_mix()
	for file in FILES:
		_players.append(EngineAudio.make_player(self, EngineAudio.load_stream(DIR + file, true), &"Tires"))


func bind(p_car: CarSim) -> void:
	car = p_car


func _process(delta: float) -> void:
	if car == null:
		return
	var t := Tuning.d
	var rate := delta / maxf(float(mix["tire_xfade_time"]), 0.001)
	var state := -1
	match car.tire_zone:
		CarSim.Zone.ONE:
			state = 0
		CarSim.Zone.TWO, CarSim.Zone.THREE:
			state = 1
		CarSim.Zone.STRUGGLE:
			state = 2
	var tire_db: Array = mix["tire_db"]
	# 每个状态内部，越接近下一个状态越响一点（−4 dB 到 0 dB）
	var within: Array[float] = [
		inverse_lerp(t.t22_zone1_start, t.t23_zone2_start, car.ratio),
		inverse_lerp(t.t23_zone2_start, 1.0, car.ratio),
		1.0,
	]
	for i in 3:
		_fade[i] = move_toward(_fade[i], 1.0 if state == i else 0.0, rate)
		var gain := _fade[i] * db_to_linear(float(tire_db[i]) + lerpf(-4.0, 0.0, clampf(within[i], 0.0, 1.0)))
		_players[i].volume_db = linear_to_db(gain) if gain > 0.0001 else EngineAudio.SILENT_DB
