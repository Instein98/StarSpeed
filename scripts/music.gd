class_name Music
extends Node
## 音乐（规格 10.2）：
##   M-01 星速：随车速渐入渐出，增益 = smoothstep(T-44 起点, T-44 满值, v_fx)；
##        增益为 0 时暂停并保留位置，再起来时从停下的地方接着放。
##   M-02 氛围：标题、点火、车库里（车速 ≤ 20 km/h）、结算时播放，2 秒淡入淡出。
## 现在两首都是 tools/make_music.py 合成的临时音乐。

const DIR := "res://assets/audio/music/"
const STAR_DB := -4.0
const AMBIENT_DB := -12.0
const AMBIENT_FADE := 2.0
const GARAGE_KMH := 20.0

var main: Node
var _star: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _ambient_gain := 0.0


func _ready() -> void:
	_star = _make("star")
	_ambient = _make("ambient")


func _make(file: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	p.stream = EngineAudio.load_stream(DIR + file + ".ogg", true)
	p.volume_db = -80.0
	add_child(p)
	return p


func _process(delta: float) -> void:
	if main == null:
		return
	var t := Tuning.d
	var v_fx: float = main.camera_rig.v_fx
	var star_gain := smoothstep(t.t44_fade_start_kmh, t.t44_fade_full_kmh, v_fx)
	_set_gain(_star, star_gain, STAR_DB)

	var flow: RunFlow = main.flow
	var calm := flow.state in [RunFlow.State.TITLE, RunFlow.State.IGNITE, RunFlow.State.IGNITING, RunFlow.State.RESULTS, RunFlow.State.ENDING, RunFlow.State.INVITE, RunFlow.State.INTRO]
	if flow.state == RunFlow.State.BASE:
		calm = true
	elif main.car.path_id == Track.PATH_ACCESS and main.car.v * 3.6 <= GARAGE_KMH and main.car.s < 20.0:
		calm = true
	_ambient_gain = move_toward(_ambient_gain, 1.0 if calm else 0.0, delta / AMBIENT_FADE)
	_set_gain(_ambient, _ambient_gain, AMBIENT_DB)


## 增益 0 时暂停（保留位置），大于 0 时接着放。
func _set_gain(p: AudioStreamPlayer, gain: float, base_db: float) -> void:
	if p.stream == null:
		return
	if gain <= 0.001:
		if p.playing:
			p.stream_paused = true
		return
	p.volume_db = base_db + linear_to_db(gain)
	if p.stream_paused:
		p.stream_paused = false
	elif not p.playing:
		p.play()
