extends Node
## 自动加载 `SaveData`：读写 user://save.json（规格 11.6）。
## 阶段 1 的最简版：只读写键位，并把键位应用到 InputMap。其余内容在阶段 5、6 补全。

signal changed

const PATH := "user://save.json"
const REBINDABLE: Array[String] = ["throttle", "shift_up", "shift_down"]

## keys 存物理键码；默认值就是 project.godot 里 Input Map 的默认键。
var data: Dictionary = {
	"version": 1,
	"keys": {},
	"best_total": -1.0,                  # 三个区段连着跑完的最好总用时（秒），−1 = 还没有
	"best_sections": [-1.0, -1.0, -1.0], # 各区段的最好用时
}


func _ready() -> void:
	for action in REBINDABLE:
		data["keys"][action] = _current_key(action)
	_load()
	_apply_keys()


func set_key(action: String, physical_keycode: int) -> void:
	data["keys"][action] = physical_keycode
	_apply_keys()
	save()
	changed.emit()


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
	var keys: Variant = (parsed as Dictionary).get("keys")
	if keys is Dictionary:
		for action in REBINDABLE:
			if (keys as Dictionary).has(action):
				data["keys"][action] = int(keys[action])


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
