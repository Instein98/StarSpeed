extends SceneTree
## 整体回归（开发者 2026-11-19 第 5 轮 #3）：大本营出发 → 出库路 → 岔路口 → 三段 → 结尾，把各个系统串起来跑一遍。
## 模拟驾驶员按理想车速曲线（PaceProfile）的 93% 开，用自动挡。结束后把存档原文写回，幽灵记录写到 user://ghost_e2e.json 再删掉。
## 用法（headless，约 1 分钟）：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . --audio-driver Dummy --fixed-fps 60 --script tools/e2e_run.gd
## 期望：进入结尾（state=7），三段都有用时，没有脚本错误。
var scene
var car
var done := false
func _initialize() -> void:
	await process_frame
	var SD = root.get_node("SaveData")
	var keep = SD.data.duplicate(true)
	var raw := FileAccess.get_file_as_string(SD.PATH)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.ghost.save_path = "user://ghost_e2e.json"
	car = scene.get_node("CarSim")
	var f = scene.flow
	f.enter_base()
	f._select = 0
	f._leave_base()
	car.use_device_input = false
	car.auto_shift = true
	var pp = scene.pace_profile
	var t := 0.0
	var log := []
	var last_state = -1
	var frames := 0
	while t < 600.0 and f.state != RunFlow.State.ENDING:
		var target := 140.0 / 3.6
		if car.path_id != Track.PATH_ACCESS:
			target = 0.93 * pp.ideal(car.path_id, car.s + car.v * 0.25)
		car.brake = car.v > target * 1.01
		car.set_throttle(car.v < target and not car.brake)
		if not car.shifting:
			car._auto_shift()
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		frames += 1
		if f.state != last_state:
			log.append("t=%.1f state=%d path=%d s=%d" % [t, f.state, car.path_id, int(car.s)])
			last_state = f.state
	print("\n".join(log))
	print("end: t=%.1f state=%d times=%s crashes=%d top=%d perfect=%s rank=%d" % [t, f.state, str(f.section_times), f.run_crashes, int(f.run_top_kmh), str(scene.corner_judge.counts), f.run_rank])
	print("ghost curves: ", scene.ghost.best.map(func(b): return b.size()), " achievements pending: ", Achievements.pending)
	var ok: bool = f.state == RunFlow.State.ENDING and not f.section_times.has(-1.0)
	print("结果：", "通过" if ok else "失败")
	if FileAccess.file_exists("user://ghost_e2e.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ghost_e2e.json"))
	Achievements.pending.clear()
	var g := FileAccess.open(SD.PATH, FileAccess.WRITE); g.store_string(raw); g.close()
	SD.data = keep
	quit(0)
