class_name Sfx
extends Node
## 一次性音效（规格 10.3）：按名字播放 assets/audio/sfx/<名字>.wav。缺文件时静音。
## 同一个名字只有一个播放器，重复播放会从头开始。

const DIR := "res://assets/audio/sfx/"

var _players: Dictionary = {}


func play(sfx_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := _player(sfx_name)
	if p.stream == null:
		return
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func stop(sfx_name: String) -> void:
	if _players.has(sfx_name):
		(_players[sfx_name] as AudioStreamPlayer).stop()


func _player(sfx_name: String) -> AudioStreamPlayer:
	if _players.has(sfx_name):
		return _players[sfx_name]
	var p := AudioStreamPlayer.new()
	# 界面音（菜单、字幕）走 UI 总线，不受驾驶里的声音处理影响
	p.bus = &"UI" if (sfx_name.begins_with("ui_") or sfx_name == "comm") else &"SFX"
	p.stream = EngineAudio.load_stream(DIR + sfx_name + ".wav", false)
	add_child(p)
	_players[sfx_name] = p
	return p
