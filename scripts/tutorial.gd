class_name Tutorial
extends Node
## 练习环道上的教学（规格 6.4 的教学表，按现在的操作改过：现在有刹车，轮胎声是三个状态）。
## CEO 的话以字幕条出现。步骤字幕一直显示到该步完成；提示类字幕显示完各自的时长后恢复步骤字幕。
## 教学完成写入存档 tutorial_done；之后练习时只保留"环道失败时"那一条。
## 教学进度只在本次练习内有效，回大本营后没完成的从步骤 0 重来。
## 另有一条只出现一次的主赛道提示（tip_downshift_shown）：按住油门 2 秒以上且转速一直低于 5000 转。

const SPEAKER := "CEO"
const STEP0_KMH := 20.0
const UPSHIFT_LO := 6500.0
const UPSHIFT_HI := 8000.0
const UPSHIFT_EARLY := 6000.0
const UPSHIFTS_NEEDED := 3
const EARLY_HINT_COOLDOWN := 12.0
const STEP2_EXTRA_DELAY := 2.0
const STEP2_EXTRA_TIME := 5.0
const ZONE_HINT_TIME := 3.0
const STEP4_TIME := 6.0
const END_TIME := 6.0
const FAIL_TIME := 3.0
const LAPS_FALLBACK := 2
const TIP_HOLD := 2.0
const TIP_RPM := 5000.0
const TIP_TIME := 4.0

var main: Node
var car: CarSim
var flow: RunFlow

var _active := false
var _step := 0
var _step_text := ""
var _hint_left := 0.0
var _upshifts := 0
var _early_cooldown := 0.0
var _step2_done_t := -1.0
var _zones_seen := {}
var _laps := 0
var _prev_loop_s := -1.0
var _step_t := 0.0
var _limiter_hint := false
var _tip_hold := 0.0


func setup(p_main: Node, p_car: CarSim, p_flow: RunFlow) -> void:
	main = p_main
	car = p_car
	flow = p_flow
	car.shift_started.connect(_on_shift)
	car.failed.connect(_on_failed)
	car.tire_zone_changed.connect(_on_zone)


## 进入练习时调用。
func start() -> void:
	_active = not bool(SaveData.data.get("tutorial_done", false))
	_hint_left = 0.0
	_upshifts = 0
	_zones_seen = {}
	_laps = 0
	_prev_loop_s = -1.0
	_step2_done_t = -1.0
	_limiter_hint = false
	if _active:
		_set_step(0)


func stop() -> void:
	if _active or _hint_left > 0.0:
		flow.hide_caption()
	_active = false
	_hint_left = 0.0


func _k(action: String) -> String:
	return "[%s]" % SaveData.key_label(action)


func _text(step: int) -> String:
	match step:
		0: return Loc.t("看见了吧。前面那条路，开出去。按住 %s 就是油门。") % _k("throttle")
		1: return Loc.t("指针到 7800 转、进红区之前，按 %s 升档。") % _k("shift_up")
		2: return Loc.t("想慢下来：按 %s 刹车。也可以松开油门、按 %s 降档，让引擎把车拖住。") % [_k("brake"), _k("shift_down")]
		3: return Loc.t("过弯听轮胎。")
		4: return Loc.t("现在故意开快一点进弯。车往外滑的时候，松油门、刹车或者降档，把它救回来。")
	return ""


func _set_step(step: int) -> void:
	_step = step
	_step_t = 0.0
	if step >= 1:
		main.sfx.play("ui_ok")      # S-31：每个步骤完成时
	if step > 4:
		_finish()
		return
	_step_text = _text(step)
	if step == 3:
		_zones_seen = {}
		_laps = 0
	if _hint_left <= 0.0:
		flow.show_caption(SPEAKER, _step_text, -1.0)


func _finish() -> void:
	_active = false
	SaveData.data["tutorial_done"] = true
	SaveData.save()
	_hint(Loc.t("可以了。按 [回车] 回大本营，选「主赛道 计时赛」。绕地球一圈，回来见。"), END_TIME)


## 提示类字幕：显示 seconds 秒，之后恢复当前步骤的字幕。
func _hint(text: String, seconds: float) -> void:
	_hint_left = seconds
	flow.show_caption(SPEAKER, text, -1.0)


func _process(delta: float) -> void:
	if car == null or flow == null:
		return
	_tip_check(delta)
	if flow.state != RunFlow.State.PRACTICE:
		if _active or _hint_left > 0.0:
			stop()
		return
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0:
			if _active:
				flow.caption_text = _step_text   # 恢复步骤字幕（不再响一次通讯声）
				flow.caption_speaker = SPEAKER
				flow.caption_left = -1.0
			else:
				flow.hide_caption()
	if not _active:
		return
	_step_t += delta
	_early_cooldown = maxf(0.0, _early_cooldown - delta)
	match _step:
		0:
			if car.v * 3.6 > STEP0_KMH:
				_set_step(1)
		1:
			# 提示 b：进入断油时一直显示，离开断油就恢复
			if car.limiter_active and not _limiter_hint:
				_limiter_hint = true
				_hint(Loc.t("顶到头了！升档，或者松油门。再顶下去引擎会炸。"), 999.0)
			elif not car.limiter_active and _limiter_hint:
				_limiter_hint = false
				_hint_left = 0.001
			if _upshifts >= UPSHIFTS_NEEDED:
				_set_step(2)
		2:
			if _step2_done_t < 0.0 and car.brake:
				_step2_done()
		3:
			_count_laps()
			var all_seen := _zones_seen.has(0) and _zones_seen.has(1)
			if all_seen or _laps >= LAPS_FALLBACK:
				_set_step(4)
		4:
			if _step_t >= STEP4_TIME:
				_set_step(5)
	if _step2_done_t >= 0.0:
		_step2_done_t += delta
		if _step2_done_t >= STEP2_EXTRA_DELAY:
			_step2_done_t = -1.0
			_set_step(3)
			_hint(Loc.t("降档别太急。转速冲过表盘尽头，引擎当场报废。等指针落下来，再降下一档。"), STEP2_EXTRA_TIME)


func _step2_done() -> void:
	_step2_done_t = 0.0
	main.sfx.play("ui_ok")


func _on_shift(is_up: bool, _from: int, _to: int) -> void:
	if not _active:
		return
	if _step == 1 and is_up:
		var r := car.shift_rpm_from
		if r >= UPSHIFT_LO and r <= UPSHIFT_HI:
			_upshifts += 1
		elif r < UPSHIFT_EARLY and _early_cooldown <= 0.0:
			_early_cooldown = EARLY_HINT_COOLDOWN
			_hint(Loc.t("升早了，动力发肉。等指针再往上走。"), 3.0)
	elif _step == 2 and not is_up and not car.throttle and _step2_done_t < 0.0:
		_step2_done()


func _on_zone(zone: int) -> void:
	if not _active or _step != 3:
		return
	var state := -1
	match zone:
		CarSim.Zone.ONE: state = 0
		CarSim.Zone.TWO, CarSim.Zone.THREE: state = 1
		CarSim.Zone.STRUGGLE: state = 2
	if state < 0 or _zones_seen.has(state):
		return
	_zones_seen[state] = true
	var lines := [Loc.t("轻的吱吱声：接近极限了。"), Loc.t("又尖又响的叫声：已经在极限上，这就是最快的过弯速度。稳住它。"),
			Loc.t("粗糙的摩擦声：车在往外滑。松油门或者刹车，把它救回来。")]
	_hint(lines[state], ZONE_HINT_TIME)


func _on_failed(_kind: int) -> void:
	if flow.state == RunFlow.State.PRACTICE:
		_hint(Loc.t("没关系，这里随便试。再来。"), FAIL_TIME)


func _count_laps() -> void:
	if car.path_id != Track.PATH_LOOP:
		return
	if _prev_loop_s >= 0.0 and car.s < _prev_loop_s - 100.0:
		_laps += 1
	_prev_loop_s = car.s


## 主赛道上只出现一次的提示：按住油门 2 秒以上、转速一直低于 5000 转。
func _tip_check(delta: float) -> void:
	if bool(SaveData.data.get("tip_downshift_shown", false)) or flow.state != RunFlow.State.RUN:
		_tip_hold = 0.0
		return
	if car.path_id == Track.PATH_MAIN and car.throttle and car.rpm < TIP_RPM and not car.shifting and car.gear > 1:
		_tip_hold += delta
		if _tip_hold >= TIP_HOLD:
			SaveData.data["tip_downshift_shown"] = true
			SaveData.save()
			flow.show_caption(SPEAKER, Loc.t("没劲了就按着油门降一档。转速上去，推力就回来了。"), TIP_TIME)
	else:
		_tip_hold = 0.0
