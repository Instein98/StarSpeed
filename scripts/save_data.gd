extends Node
## 自动加载 `SaveData`：读写 user://save.json（规格 11.6）。
## 阶段 1 的最简版：只读写键位，并把键位应用到 InputMap。其余内容在阶段 5、6 补全。

signal changed
## 设置改了（main 据此把自动挡开关传给 CarSim）
signal settings_applied

const PATH := "user://save.json"
const REBINDABLE: Array[String] = ["throttle", "brake", "shift_up", "shift_down"]
## 不能绑定的键（4.1）：Esc、回车、F1 – F5
const FORBIDDEN: Array[int] = [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_R]
## 存档里的开关：开场看过、教学完成、降档提示出现过、降档提示灯辅助（R-06a）
const FLAGS: Array[String] = ["intro_seen", "tutorial_done", "tip_downshift_shown", "assist_downshift_lamp"]

## keys 存物理键码；默认值就是 project.godot 里 Input Map 的默认键。
var data: Dictionary = {
	"version": 1,
	"keys": {},
	"best_total": -1.0,                  # 三个区段连着跑完的最好总用时（秒），−1 = 还没有
	"best_sections": [-1.0, -1.0, -1.0], # 各区段的最好用时
	"best_medals": [0, 0, 0],            # 各区段拿过的最高贴纸等级：0 没有、1 塑料、2 铜、3 银、4 金
	"intro_seen": false,
	"tutorial_done": false,
	"tip_downshift_shown": false,
	"assist_downshift_lamp": false,
	"lang": "zh",
	# 设置（开发者 2026-11-19 第 1 轮 #4）：音量 0–10，全屏，幽灵
	"vol_master": 8,
	"vol_music": 8,
	"vol_sfx": 8,
	"fullscreen": true,
	"ghost_on": true,
	"auto_shift": false,
}

## 音量设置对应的总线：音效 = 引擎、风声、音效（都经过 World）+ 轮胎 + 界面音
const VOLUME_BUSES := {"vol_master": ["Master"], "vol_music": ["Music"], "vol_sfx": ["World", "Tires", "UI"]}
var _bus_base_db := {}


func _ready() -> void:
	for action in REBINDABLE:
		data["keys"][action] = _current_key(action)
	# 9.13：首次启动按系统语言决定，之后以存档为准
	data["lang"] = "zh" if OS.get_locale_language() == "zh" else "en"
	_load()
	_apply_keys()
	apply_settings()


## 把音量、全屏设置应用上去。音量 10 = 总线原来的音量，0 = 静音，中间按分贝线性（每档约 3 dB）。
func apply_settings() -> void:
	settings_applied.emit()
	for key: String in VOLUME_BUSES:
		var v := clampi(int(data.get(key, 8)), 0, 10)
		for bus_name: String in VOLUME_BUSES[key]:
			var idx := AudioServer.get_bus_index(bus_name)
			if idx < 0:
				continue
			if not _bus_base_db.has(bus_name):
				_bus_base_db[bus_name] = AudioServer.get_bus_volume_db(idx)
			AudioServer.set_bus_volume_db(idx, float(_bus_base_db[bus_name]) + (v - 10) * 3.0 if v > 0 else -80.0)
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(data.get("fullscreen", true)) else DisplayServer.WINDOW_MODE_WINDOWED
		var now := DisplayServer.window_get_mode()
		var is_full := now == DisplayServer.WINDOW_MODE_FULLSCREEN or now == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if is_full != (want == DisplayServer.WINDOW_MODE_FULLSCREEN):
			DisplayServer.window_set_mode(want)
			if want == DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_size(Vector2i(1600, 900))
				var screen := DisplayServer.screen_get_size()
				DisplayServer.window_set_position((screen - Vector2i(1600, 900)) / 2)


## 清除成绩：最好成绩、区段最好、奖牌、幽灵记录。键位、语言、设置、开场和教学进度保留。
func clear_records() -> void:
	data["best_total"] = -1.0
	data["best_sections"] = [-1.0, -1.0, -1.0]
	data["best_medals"] = [0, 0, 0]
	save()
	if FileAccess.file_exists(Ghost.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Ghost.PATH))
	changed.emit()


## 改键（4.1、9.10）：绑定已被别的动作占用的键时两个动作互换。返回 false = 这个键不允许。
func set_key(action: String, physical_keycode: int) -> bool:
	if physical_keycode in FORBIDDEN:
		return false
	var old: int = data["keys"][action]
	for other in REBINDABLE:
		if other != action and int(data["keys"][other]) == physical_keycode:
			data["keys"][other] = old
			_bind(other, old)
	data["keys"][action] = physical_keycode
	_bind(action, physical_keycode)
	save()
	changed.emit()
	return true


## 恢复默认键位（以及降档提示灯辅助开关）。
func reset_keys() -> void:
	InputMap.load_from_project_settings()
	for action in REBINDABLE:
		data["keys"][action] = _current_key(action)
	data["assist_downshift_lamp"] = false
	save()
	changed.emit()


func _bind(action: String, code: int) -> void:
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	InputMap.action_add_event(action, ev)


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("存档写入失败: " + PATH)
		return
	f.store_string(JSON.stringify(data, "  "))


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		return   # 无法解析时使用默认值
	var best_total: Variant = (parsed as Dictionary).get("best_total")
	if best_total is float or best_total is int:
		data["best_total"] = float(best_total)
	var best_sections: Variant = (parsed as Dictionary).get("best_sections")
	if best_sections is Array and (best_sections as Array).size() == 3:
		data["best_sections"] = [float(best_sections[0]), float(best_sections[1]), float(best_sections[2])]
	var medals: Variant = (parsed as Dictionary).get("best_medals")
	if medals is Array and (medals as Array).size() == 3:
		data["best_medals"] = [int(medals[0]), int(medals[1]), int(medals[2])]
	# 已经有存档、但存档里还没有语言设置的（加语言切换之前就在玩的），保持中文
	var saved_lang: Variant = (parsed as Dictionary).get("lang", "zh")
	if saved_lang is String and saved_lang in ["zh", "en"]:
		data["lang"] = saved_lang
	for flag: String in FLAGS:
		if (parsed as Dictionary).has(flag):
			data[flag] = bool((parsed as Dictionary)[flag])
	var keys: Variant = (parsed as Dictionary).get("keys")
	if keys is Dictionary:
		for action in REBINDABLE:
			if (keys as Dictionary).has(action):
				data["keys"][action] = int(keys[action])


## 界面上显示的键名（9.10）：空格显示"空格"，方向键显示箭头，字母数字显示大写，其余用引擎的英文键名。
## 一个动作绑了几个键时用" / "连起来。
func key_label(action: String) -> String:
	var names := PackedStringArray()
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var code := (ev as InputEventKey).physical_keycode
			if code == 0:
				code = (ev as InputEventKey).keycode
			names.append(key_name(code))
	return " / ".join(names)


static func key_name(code: int) -> String:
	match code:
		KEY_SPACE: return Loc.t("空格")
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
		KEY_ENTER, KEY_KP_ENTER: return Loc.t("回车")
	return OS.get_keycode_string(code).to_upper()


func _current_key(action: String) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return (ev as InputEventKey).physical_keycode
	return 0


func _apply_keys() -> void:
	for action in REBINDABLE:
		var code: int = data["keys"][action]
		# 存的键就是默认的第一个键时不动 Input Map，这样默认的第二个键（如油门的 W）不会被清掉
		if code == 0 or code == _current_key(action):
			continue
		InputMap.action_erase_events(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		InputMap.action_add_event(action, ev)
