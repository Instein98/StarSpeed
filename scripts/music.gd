class_name Music
extends Node
## 音乐：
##   M-01 星速，分三层（开发者 2026-11-16，替代规格"随车速渐入"）：
##        底轨（贝斯、铺底、踩镲）：计时赛和练习里一直有（车在车库里除外）；
##        鼓：车速 ÷ 理想车速（PaceProfile）≥ music_drums_on 时加入；
##        主音：≥ music_lead_on 时加入。
##        退出有防抖：比例低于退出线并持续 music_off_hold_s 才退；撞车、爆缸时鼓和主音快速淡出。
##        三层放在一个 AudioStreamSynchronized 里，始终同步；全部静音时暂停并保留位置。
##   M-02 氛围：标题、点火、车库里（车速 ≤ 20 km/h）、结算时播放，2 秒淡入淡出。
## 现在都是 tools/make_music.py 合成的临时音乐。

const DIR := "res://assets/audio/music/"
const STAR_DB := -4.0
const AMBIENT_DB := -12.0
const AMBIENT_FADE := 2.0
const GARAGE_KMH := 20.0
const LAYERS := ["base", "drums", "lead"]
## 三个区段各一首（第 3 轮 #6）：森林 star_*、冰原 star_ice_*、城市 star_city_*。过区段线时 2 秒交叉淡入淡出。
const SECTION_TRACKS := ["star", "star_ice", "star_city"]
const SECTION_FADE := 2.0
enum { BASE, DRUMS, LEAD }

var main: Node
var _players: Array[AudioStreamPlayer] = []
var _syncs: Array[AudioStreamSynchronized] = []
var _sec_gain := [1.0, 0.0, 0.0]
var _ambient: AudioStreamPlayer
var _ambient_gain := 0.0
var _gain := [0.0, 0.0, 0.0]
var _on := [false, false, false]
var _below := [0.0, 0.0, 0.0]          ## 低于退出线已经多久
var _fail_cut := false                 ## 撞车后鼓和主音正在快速淡出
## 平滑后的 车速 ÷ 理想车速（调试面板也读它）
var pace := 0.0


func _ready() -> void:
	for track in SECTION_TRACKS:
		var sync := AudioStreamSynchronized.new()
		sync.stream_count = LAYERS.size()
		for i in LAYERS.size():
			sync.set_sync_stream(i, EngineAudio.load_stream(DIR + track + "_" + LAYERS[i] + ".ogg", true))
			sync.set_sync_stream_volume(i, -80.0)
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.stream = sync
		p.volume_db = STAR_DB
		add_child(p)
		_syncs.append(sync)
		_players.append(p)
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
	var flow: RunFlow = main.flow
	var car: CarSim = main.car
	var calm := flow.state in [RunFlow.State.TITLE, RunFlow.State.IGNITE, RunFlow.State.IGNITING, RunFlow.State.RESULTS, RunFlow.State.ENDING, RunFlow.State.INVITE, RunFlow.State.INTRO]
	if flow.state == RunFlow.State.BASE:
		calm = true
	elif car.path_id == Track.PATH_ACCESS and car.v * 3.6 <= GARAGE_KMH and car.s < 20.0:
		calm = true
	_ambient_gain = move_toward(_ambient_gain, 1.0 if calm else 0.0, delta / AMBIENT_FADE)
	_set_gain(_ambient, _ambient_gain, AMBIENT_DB)

	var driving := not calm and flow.state in [RunFlow.State.RUN, RunFlow.State.PRACTICE]
	_update_star(delta, driving, car)


func _update_star(delta: float, driving: bool, car: CarSim) -> void:
	var t := Tuning.d
	var raw: float = main.pace_profile.pace(car.path_id, car.s, car.v) if main.pace_profile else -1.0
	raw = maxf(raw, 0.0)
	pace = lerpf(pace, raw, 1.0 - exp(-delta / maxf(t.music_pace_smooth_s, 0.001)))
	var exploding := car.mode != CarSim.Mode.DRIVE or bool(main.get("_fail_phase"))
	if exploding:
		_fail_cut = true
	_on[BASE] = driving
	_layer(DRUMS, driving and not exploding, t.music_drums_on, t.music_drums_off, delta)
	_layer(LEAD, driving and not exploding, t.music_lead_on, t.music_lead_off, delta)
	# 复位后不会立刻回来：鼓和主音要等比例重新达到加入线
	if _fail_cut and _gain[DRUMS] <= 0.0 and _gain[LEAD] <= 0.0:
		_fail_cut = false

	for i in LAYERS.size():
		var fade: float = t.music_fade_in_s if _on[i] else t.music_fade_out_s
		if _fail_cut and i != BASE:
			fade = t.music_fail_fade_s
		_gain[i] = move_toward(_gain[i], 1.0 if _on[i] else 0.0, delta / maxf(fade, 0.01))
	var any: bool = _gain.any(func(g): return g > 0.001)
	# 现在是哪个区段的曲子：主赛道按里程，其余（出库路、环道）用森林那首
	var want := 0
	if car.path_id == Track.PATH_MAIN:
		want = clampi(main.track.section_index_at(car.s), 0, SECTION_TRACKS.size() - 1)
	for k in SECTION_TRACKS.size():
		_sec_gain[k] = move_toward(_sec_gain[k], 1.0 if k == want else 0.0, delta / SECTION_FADE)
		var p := _players[k]
		for i in LAYERS.size():
			_syncs[k].set_sync_stream_volume(i, linear_to_db(maxf(_gain[i], 0.0001)))
		p.volume_db = STAR_DB + linear_to_db(maxf(_sec_gain[k], 0.0001))
		if not any or _sec_gain[k] <= 0.001:
			if p.playing:
				p.stream_paused = true
		elif p.stream_paused:
			p.stream_paused = false
		elif not p.playing:
			p.play()


## 一层的加入 / 退出（带防抖）。
func _layer(i: int, allowed: bool, on_at: float, off_at: float, delta: float) -> void:
	if not allowed:
		_on[i] = false
		_below[i] = 0.0
		return
	if not _on[i]:
		if pace >= on_at:
			_on[i] = true
			_below[i] = 0.0
		return
	if pace < off_at:
		_below[i] += delta
		if _below[i] >= Tuning.d.music_off_hold_s:
			_on[i] = false
	else:
		_below[i] = 0.0


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
