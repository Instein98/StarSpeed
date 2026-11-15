class_name EngineAudio
extends Node
## 第 10.4 节引擎混合（基本版）：4 个转速层 × 加油 / 松油两套 + 断油限速声。
## 外星嗡鸣、回火、换挡音效、混音面板在阶段 7 补全。
## 任何音频文件缺失时该声音静音，并在日志里输出一行文件名（10.1）。

const DEFAULT_MIX_PATH := "res://data/engine_mix_default.json"
const USER_MIX_PATH := "user://engine_mix.json"
const DIR := "res://assets/audio/engine/"
const LAYER_FILES: Array[String] = ["2000", "3500", "5500", "8000"]
const SILENT_DB := -80.0

var car: CarSim
var mix: Dictionary = {}

var _on: Array[AudioStreamPlayer] = []
var _off: Array[AudioStreamPlayer] = []
var _limiter: AudioStreamPlayer
## 听到的转速。车的转速在换挡瞬间是直接跳到新档位的值的；声音不能跳，要很快地扫过去，
## 这样降档听起来是"轰一脚油"，升档是转速落下去。
var audio_rpm := 0.0
## 大于 0 时声音的转速朝这个值冲（降档爆缸的演出用：转速被拉过红线），否则跟车的转速。
var rev_target := -1.0
var _gate_phase := 0.0
var _on_blend := 0.0      # 0 = 松油套，1 = 加油套
var _shift_gain := 1.0    # 升档动力中断时的压低


## 读取混音参数：默认文件，再用 user:// 里保存过的值覆盖。
static func load_mix() -> Dictionary:
	var result: Dictionary = {}
	for path: String in [DEFAULT_MIX_PATH, USER_MIX_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			result.merge(parsed as Dictionary, true)
	return result


## 读取一个音频文件并设为循环；缺失时返回 null 并记一行日志。
static func load_stream(path: String, loop: bool) -> AudioStream:
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	elif FileAccess.file_exists(path):
		# 文件已放入但编辑器还没导入：直接从磁盘读
		var abs_path := ProjectSettings.globalize_path(path)
		if path.ends_with(".ogg"):
			stream = AudioStreamOggVorbis.load_from_file(abs_path)
		elif path.ends_with(".wav"):
			stream = AudioStreamWAV.load_from_file(abs_path)
	if stream == null:
		print("[audio] 缺少音频文件，静音: ", path)
		return null
	if loop:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


static func make_player(parent: Node, stream: AudioStream, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = SILENT_DB
	parent.add_child(p)
	if stream != null:
		p.play()
	return p


func _ready() -> void:
	mix = load_mix()
	for name_part in LAYER_FILES:
		_on.append(make_player(self, load_stream(DIR + "on_" + name_part + ".ogg", true), &"Engine"))
		_off.append(make_player(self, load_stream(DIR + "off_" + name_part + ".ogg", true), &"Engine"))
	_limiter = make_player(self, load_stream(DIR + "limiter.ogg", true), &"Engine")


func _process(delta: float) -> void:
	if car == null:
		return
	var target_rpm := rev_target if rev_target > 0.0 else car.rpm
	if audio_rpm <= 0.0:
		audio_rpm = target_rpm
	audio_rpm = move_toward(audio_rpm, target_rpm, float(mix.get("rpm_slew_per_sec", 10000.0)) * delta)
	var rpm := audio_rpm
	var layer_rpm: Array = mix["layer_rpm"]
	var n := layer_rpm.size()

	# 层音量：相邻两层等功率交叉过渡，其余静音
	var gains: Array[float] = []
	gains.resize(n)
	gains.fill(0.0)
	if rpm <= float(layer_rpm[0]):
		gains[0] = 1.0
	elif rpm >= float(layer_rpm[n - 1]):
		gains[n - 1] = 1.0
	else:
		for i in n - 1:
			var lo := float(layer_rpm[i])
			var hi := float(layer_rpm[i + 1])
			if rpm >= lo and rpm < hi:
				var x := (rpm - lo) / (hi - lo)
				x = clampf((x - 0.5) / maxf(float(mix["overlap"]), 0.01) + 0.5, 0.0, 1.0)
				gains[i] = cos(x * PI * 0.5)
				gains[i + 1] = sin(x * PI * 0.5)
				break

	# 加油 / 松油两套，0.08 秒内交叉过渡
	var rate := delta / maxf(float(mix["on_off_time"]), 0.001)
	# 开发者 2026-11-14 试玩后的要求：引擎的音量只跟转速走，与油门、换挡、断油无关。
	# 所以规格 10.4 里的"升档静音""松油套 −4 dB""断油时加油套 −6 dB"都不再压低音量
	# （对应的混音参数现在都是 0 dB）；加油 / 松油只换音色，不换响度。
	# 第二次反馈：踩油门时仍然明显更响——两套录音本身的音色和响度不一样。
	# 所以默认只用加油那一套（use_off_set = false），声音只随转速变。
	var want_on := car.throttle or not bool(mix.get("use_off_set", false))
	_on_blend = move_toward(_on_blend, 1.0 if want_on else 0.0, rate)
	var cutting := car.shifting and car.shift_is_up
	var cut_gain := db_to_linear(float(mix.get("shift_cut_db", 0.0)))
	_shift_gain = move_toward(_shift_gain, cut_gain if cutting else 1.0, delta / maxf(float(mix["shift_fade_time"]), 0.001))
	# 转速越高越响：怠速时 rpm_gain_min_db，到断油转速时 0 dB
	var rpm_f := clampf((rpm - Tuning.d.t03_idle_rpm) / (Tuning.d.t05_cut_rpm - Tuning.d.t03_idle_rpm), 0.0, 1.0)
	var rpm_gain := db_to_linear(lerpf(float(mix.get("rpm_gain_min_db", 0.0)), 0.0, rpm_f))

	# 加油和松油两套按等功率交叉，过渡中总响度不变
	var on_gain := sin(_on_blend * PI * 0.5) * _shift_gain * rpm_gain
	var off_gain := cos(_on_blend * PI * 0.5) * _shift_gain * rpm_gain * db_to_linear(float(mix["off_set_db"]))
	var pitch_min := float(mix["pitch_min"])
	var pitch_max := float(mix["pitch_max"])
	var on_db: Array = mix["layer_on_db"]
	var off_db: Array = mix["layer_off_db"]
	# 断油：到了断油转速，引擎声自己一断一续（"嘟嘟嘟"），真实的断油就是点火被切掉又恢复。
	# 断续的频率随过转计时器从 limiter_gate_hz 升到 limiter_gate_hz_max，越接近爆缸越急（R-09a 的提示作用）。
	var gate := 1.0
	var gate_pitch := 1.0
	if rpm >= Tuning.d.t05_cut_rpm - 1.0:
		var urgency := clampf(car.overrev_timer / Tuning.d.t11_overrev_limit, 0.0, 1.0)
		var hz := lerpf(float(mix.get("limiter_gate_hz", 11.0)), float(mix.get("limiter_gate_hz_max", 18.0)), urgency)
		_gate_phase = fposmod(_gate_phase + delta * hz, 1.0)
		if _gate_phase > float(mix.get("limiter_gate_duty", 0.55)):
			gate = db_to_linear(float(mix.get("limiter_gate_cut_db", -30.0)))
			gate_pitch = 0.94          # 切掉的那一下转速略微掉一点
	else:
		_gate_phase = 0.0
	on_gain *= gate
	off_gain *= gate
	for i in n:
		var pitch := clampf(rpm / float(layer_rpm[i]), pitch_min, pitch_max) * gate_pitch
		_apply(_on[i], gains[i] * on_gain * db_to_linear(float(on_db[i])), pitch)
		_apply(_off[i], gains[i] * off_gain * db_to_linear(float(off_db[i])), pitch)

	# limiter.ogg 不再使用（开发者反馈：那一声"叮"不真实）。断油的声音在上面用引擎声自己的断续来做。
	_apply(_limiter, 0.0, 1.0)


func _apply(player: AudioStreamPlayer, gain: float, pitch: float) -> void:
	player.volume_db = linear_to_db(gain) if gain > 0.0001 else SILENT_DB
	player.pitch_scale = pitch
