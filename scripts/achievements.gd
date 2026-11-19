class_name Achievements
extends RefCounted
## 成就（开发者 2026-11-19 第 3 轮 #3）。解锁的 id 存在存档 achievements 里。
## 检查点：跑完三段（_finish_run）、拿到奖牌（section_done）、每帧（最高车速、完美过弯、累计公里）。
## 新解锁的放进 pending，由 run_flow 逐个弹出提示。

## [id, 名字, 说明]
const LIST: Array = [
	["finish", "环球旅行", "跑完一趟三段连跑"],
	["gold", "第一枚金牌", "任意区段拿到金牌"],
	["all_gold", "全金", "三个区段都拿到金牌"],
	["clean", "零失误", "三段连跑一次都没撞"],
	["perfect10", "弯道大师", "一趟里 10 次完美过弯"],
	["perfect_all", "无可挑剔", "一趟三段连跑，评价过的弯全是完美"],
	["top", "星速", "开到 680 km/h"],
	["sub4", "四分钟以内", "三段连跑总用时进 4:00"],
	["km100", "百公里", "累计驾驶 100 km"],
	["tutorial", "毕业", "完成练习环道的教学"],
]

static var pending: Array[String] = []


static func has(id: String) -> bool:
	return id in (SaveData.data.get("achievements", []) as Array)


static func unlock(id: String) -> void:
	if has(id):
		return
	var got: Array = SaveData.data.get("achievements", [])
	got.append(id)
	SaveData.data["achievements"] = got
	SaveData.save()
	pending.append(id)


static func info(id: String) -> Array:
	for a: Array in LIST:
		if a[0] == id:
			return a
	return [id, id, ""]


static func count() -> int:
	return (SaveData.data.get("achievements", []) as Array).size()


## 成就是后来加的：启动时按存档里已有的成绩补上（不弹提示）。
static func backfill() -> void:
	var medals: Array = SaveData.data.get("best_medals", [0, 0, 0])
	var best_total := float(SaveData.data.get("best_total", -1.0))
	var ids: Array[String] = []
	if best_total >= 0.0:
		ids.append("finish")
		if best_total < 240.0:
			ids.append("sub4")
	if medals.any(func(m): return int(m) >= 4):
		ids.append("gold")
	if medals.all(func(m): return int(m) >= 4):
		ids.append("all_gold")
	if bool(SaveData.data.get("tutorial_done", false)):
		ids.append("tutorial")
	var got: Array = SaveData.data.get("achievements", [])
	var changed := false
	for id in ids:
		if not id in got:
			got.append(id)
			changed = true
	if changed:
		SaveData.data["achievements"] = got
		SaveData.save()
