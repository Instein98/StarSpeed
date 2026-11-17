class_name Loc
extends RefCounted
## 界面文字的中英文（规格 9.13）。字符串表 data/strings.csv：列为 键、zh、en；键就是中文原文。
## Loc.t("开始") 在中文下原样返回，在英文下返回 en 列；表里没有的文字原样返回。
## 首次启动按系统语言决定，之后以存档 lang 为准。

const PATH := "res://data/strings.csv"

static var _table: Dictionary = {}
static var _loaded := false


static func lang() -> String:
	return str(SaveData.data.get("lang", "zh"))


static func t(zh: String) -> String:
	if lang() != "en":
		return zh
	_load()
	return str(_table.get(zh, zh))


static func toggle() -> void:
	SaveData.data["lang"] = "en" if lang() == "zh" else "zh"
	SaveData.save()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("读不到字符串表 " + PATH)
		return
	f.get_csv_line()   # 表头
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and row[0] != "":
			_table[row[0]] = row[2]
