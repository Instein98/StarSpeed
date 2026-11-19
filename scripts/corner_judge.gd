class_name CornerJudge
extends Node
## 过弯评价（开发者 2026-11-19 第 1 轮 #6）：每过完一个弯，看这个弯里车速离极限有多近。
##   最高 车速 ÷ 极限车速 ≥ corner_perfect_ratio 且没有打滑 → "完美过弯"，亮铃声；
##   ≥ corner_great_ratio 且没有打滑 → "漂亮"，轻铃声；
##   打滑过（超过极限）或者更慢 → 不评价。
## 极限车速高于极速的大弯（怎么开都到不了极限）不评价；在弯里不足 corner_min_time 秒的也不评价。
## 只在计时赛和练习里评价。本局的计数在 counts（完美、漂亮、评价过的弯）。

const POPUP_TIME := 1.2

var main: Node
var car: CarSim
## 当前显示的评价文字和剩余时间（run_flow 画）
var popup := ""
var popup_perfect := false
var popup_t := 0.0
var counts := [0, 0, 0]

var _in := false
var _sign := 0
var _peak := 0.0
var _slid := false
var _time := 0.0
var _reachable := false


func setup(p_main: Node, p_car: CarSim) -> void:
	main = p_main
	car = p_car


func reset_counts() -> void:
	counts = [0, 0, 0]
	_in = false


func _physics_process(delta: float) -> void:
	popup_t = maxf(0.0, popup_t - delta)
	if car == null:
		return
	var state: int = main.flow.state
	var active := (state == RunFlow.State.RUN or state == RunFlow.State.PRACTICE) and car.mode == CarSim.Mode.DRIVE
	if not active:
		_in = false
		return
	var t := Tuning.d
	var curving := absf(car.kappa) >= CarSim.KAPPA_EPS
	var sgn := int(signf(car.kappa)) if curving else 0
	if _in and (not curving or sgn != _sign):
		_judge()
		_in = false
	if curving and not _in:
		_in = true
		_sign = sgn
		_peak = 0.0
		_slid = false
		_time = 0.0
		_reachable = false
	if _in:
		_time += delta
		_peak = maxf(_peak, car.ratio)
		_slid = _slid or car.ratio >= 1.0 or car.slide > 0.3
		_reachable = _reachable or car.v_lim < t.top_speed_kmh * CarSim.KMH * 0.98


func _judge() -> void:
	var t := Tuning.d
	if not _reachable or _time < t.corner_min_time:
		return
	counts[2] += 1
	if _slid:
		return
	if _peak >= t.corner_perfect_ratio:
		counts[0] += 1
		_show(Loc.t("完美过弯"), true)
	elif _peak >= t.corner_great_ratio:
		counts[1] += 1
		_show(Loc.t("漂亮"), false)


func _show(text: String, perfect: bool) -> void:
	popup = text
	popup_perfect = perfect
	popup_t = POPUP_TIME
	main.sfx.play("corner_perfect" if perfect else "corner_great", -4.0)
