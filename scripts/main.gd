extends Node
## 启动时把各节点互相连好；处理 F2 – F4（规格 11.4）。
## 临时写在这里、阶段 5 迁到 run_director.gd 的东西：R-24 原地恢复、F4 瞬移、跑完尾段回车库起点、
## 失败演出、驶出开关。
## 阶段 9 删除的东西：路两侧的测试方块。

const RECOVER_RPM_MIN := 4000.0   ## R-24
const RECOVER_RPM_MAX := 7000.0
# 失败演出（7.3 的时间线；临时写在这里，阶段 5 迁到 run_director.gd 并接上 Game Over 和进场回放）。
# 开发者 2026-11-14 的要求：先让人看得出为什么失败——冲出赛道要真的飞出去、撞上，爆缸要有爆炸——然后原地复位。
const FLASH_TIME := 0.3           ## V-07：全屏纯白，0.3 秒线性淡出
const FAIL_PRE_TIME := 0.4        ## 0.0–0.4 秒：飞出 / 爆缸；0.4 秒撞击、全白 2 帧、大爆炸开始
const FAIL_DOWNSHIFT_PRE_TIME := 0.9   ## 降档爆缸：约 0.35 秒转速冲过红线，再断油"嘟嘟"约半秒，然后爆
const FAIL_BLOW_DECEL_G := 2.0    ## 爆缸后车速按 2 g 下降
const WHITE_FRAMES := 2
const EXIT_LOCK_DISTANCE := 100.0 ## R-41：距岔路口不足 100 m 时驶出开关锁定
const WORLD_AUDIO_DIR := "res://assets/audio/world/"
const MINIMAP_VIEW_WIDTH := 0.26  ## 9.5：小地图在锚点处的视宽度相当于 0.26 m
## 9.5 给的矩形 (530, 285) – (750, 400) 里，锚点 (0.60, 0, −0.01) 的投影落在自上而下约 73% 处
const MINIMAP_ANCHOR_V := 0.727

# 测试方块（阶段 2 – 8 的临时参照物）。规格写每 30 m 一个；开发者试玩后觉得没有速度感，
# 改成每 10 m 一个、高矮不一（接近阶段 9 森林近带"每侧每 8 m 一棵树"的密度）。
const TEST_CUBE_STEP := 10
const TEST_CUBE_HEIGHTS: Array[float] = [1.0, 2.5, 1.5, 4.0, 1.0, 3.0]
const TEST_CUBE_SIZE := 2.0
const TEST_CUBE_OFFSET := 10.0
const TEST_CUBE_CLEAR := 9.0      ## 方块中心离任何赛道中心线至少 9 m（路面半宽 6 m + 方块半宽 1 m + 余量）
## 岔路口、并入口：附近有另一条方向不同的路时，方块离那条路的中心线至少 30 m。
## 否则两条路之间的夹角里会立着一排方块，从车里看就像堆在弯道上。
const TEST_CUBE_JUNCTION_CLEAR := 30.0
const TEST_CUBE_SAME_ROAD := 120.0     ## 同一条路径上沿路相隔不到 120 m 的算"自己这段路"
const TEST_CUBE_PARALLEL_DOT := 0.985   ## 两条路方向相差 10° 以内算同一条路的延续
const TEST_CUBE_COLORS: Array[Color] = [
	Color("ef4a2f"), Color("ffc93c"), Color("f7ecd4"), Color("2f9e6a"),
	Color("8a6a4a"), Color("6f9fc0"), Color("23805a"), Color("ffffff"),
]

@onready var car: CarSim = $CarSim
@onready var world_viewport: SubViewport = $WorldViewport
@onready var cockpit_viewport: SubViewport = $CockpitViewport
@onready var track: Track = $WorldViewport/Track
@onready var env_director: EnvironmentDirector = $WorldViewport/EnvironmentDirector
@onready var world_env: WorldEnvironment = $WorldViewport/WorldEnvironment
@onready var camera_rig: CameraRig = $WorldViewport/CameraRig
@onready var world_post: SpeedFx = $WorldViewport/CameraRig/WorldCamera/WorldPost
@onready var cockpit: Cockpit = $CockpitViewport/Cockpit
@onready var cockpit_camera: Camera3D = $CockpitViewport/CockpitCamera
@onready var minimap: Minimap = $CockpitViewport/MinimapViewport
@onready var vignette: ColorRect = $Screen/StruggleVignette
@onready var minimap_rect: TextureRect = $Screen/MinimapRect
@onready var world_rect: TextureRect = $Screen/WorldRect
@onready var cockpit_rect: TextureRect = $Screen/CockpitRect
@onready var overlay: Control = $UI/UIRoot/DebugOverlay
@onready var fullscreen_fade: ColorRect = $UI/UIRoot/FullscreenFade
@onready var exit_hint: Label = $UI/UIRoot/ExitSwitchHint
@onready var explosion: Explosion = $Screen/ExplosionOverlay
@onready var engine_audio: EngineAudio = $Audio/EngineAudio
@onready var tire_audio: TireAudio = $Audio/TireAudio

enum FailPhase { NONE, PRE, BOOM }

var _flash := 0.0
var _white_frames := 0
var _red_frames := 0
var _fail_phase := FailPhase.NONE
var _fail_kind := 0
var _fail_time := 0.0
var _fail_speed := 0.0
var _fail_pre_time := FAIL_PRE_TIME
var _sfx: Dictionary = {}
var _cube_colors: Array[Color] = []
# 区段计时：过了区段起点线开始计，过终点线时把用时显示在右上角，直到下一个区段跑完
var _timing_section := -1
var _section_time := 0.0
var _prev_main_s := -1.0
var _time_label: Label
var flow: RunFlow


func _ready() -> void:
	var t := Tuning.d
	world_viewport.size = t.t45_world_resolution
	cockpit_viewport.size = t.t46_cockpit_resolution
	world_rect.texture = world_viewport.get_texture()
	cockpit_rect.texture = cockpit_viewport.get_texture()

	env_director.setup(world_env, world_post.get_surface_override_material(0) as ShaderMaterial)
	track.set_material(env_director.world_material)
	_spawn_test_cubes()
	minimap_rect.texture = minimap.get_texture()
	cockpit.set_light(env_director.forest.light_color, 1.0)

	car.track = track
	car.failed.connect(_on_car_failed)
	cockpit.car = car
	camera_rig.bind(car, track, cockpit_camera)
	world_post.bind(car, track)
	minimap.bind(car, track, cockpit)
	engine_audio.car = car
	tire_audio.bind(car)
	overlay.set("car", car)
	overlay.set("track", track)
	overlay.visible = false
	for sfx_name: String in ["crash", "explosion"]:   # 爆缸前的那一声"噔"按开发者要求去掉了，直接炸
		var player := AudioStreamPlayer.new()
		player.stream = EngineAudio.load_stream(WORLD_AUDIO_DIR + sfx_name + ".wav", false)
		player.bus = &"SFX"
		$Audio.add_child(player)
		_sfx[sfx_name] = player
	_time_label = exit_hint.duplicate() as Label
	_time_label.name = "SectionTime"
	_time_label.text = ""
	_time_label.visible = true
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_font_size_override("font_size", 20)
	_time_label.add_theme_color_override("font_color", Color("f7ecd4"))
	_time_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_time_label.offset_left = -420.0
	_time_label.offset_right = -24.0
	_time_label.offset_top = 20.0
	_time_label.offset_bottom = 48.0
	exit_hint.get_parent().add_child(_time_label)
	flow = RunFlow.new()
	flow.name = "RunFlow"
	exit_hint.get_parent().add_child(flow)
	flow.setup(self, car, track, exit_hint, cockpit)
	flow.enter_base()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_reload"):
		Tuning.reload()
	elif event.is_action_pressed("debug_overlay"):
		overlay.visible = not overlay.visible
	elif event.is_action_pressed("debug_next_segment"):
		if _fail_phase == FailPhase.NONE:
			_jump_to_next_section()
			flow.debug_enter_run()
	elif event.is_action_pressed("debug_fx_mode"):
		# F5：画面方案轮换 M → A → B（T-48）；只改本次运行，选定后写回调参文件
		var modes: Array[String] = ["M", "A", "B"]
		Tuning.d.t48_fx_mode = modes[(modes.find(Tuning.d.t48_fx_mode) + 1) % modes.size()]


func _physics_process(delta: float) -> void:
	# 保险：万一开到了终点线后尾段的尽头（正常情况下结算时车会自己刹停），直接回大本营
	if car.path_id == Track.PATH_MAIN and car.s >= track.length(Track.PATH_MAIN) - 0.01:
		return_to_base()
	_update_section_timer(delta)
	# 爆缸演出的前 0.4 秒：车还在赛道上，车速按 2 g 下降
	if _fail_phase == FailPhase.PRE and _fail_kind != CarSim.Fail.OFF_TRACK:
		car.v = maxf(0.0, car.v - FAIL_BLOW_DECEL_G * CarSim.G * delta)


func _process(delta: float) -> void:
	_place_minimap()
	_update_environment()
	_update_fail_sequence(delta)
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	if _white_frames > 0:
		_white_frames -= 1
		fullscreen_fade.color = Color(1.0, 1.0, 1.0, 1.0)
	elif _red_frames > 0:
		_red_frames -= 1
		fullscreen_fade.color = Color(0.937, 0.29, 0.184, 0.6)
	else:
		fullscreen_fade.color = Color(1.0, 1.0, 1.0, _flash)
	vignette.material.set("shader_parameter/amount", car.slide_frac)


# ───────────────────────── 一局的流程（RunFlow 调用） ─────────────────────────

## 回大本营：中断正在播的失败演出，白闪一下，车回车库。
func return_to_base() -> void:
	if _fail_phase != FailPhase.NONE:
		_fail_phase = FailPhase.NONE
		explosion.stop()
		camera_rig.stop_flyoff()
		cockpit.blown = false
		engine_audio.rev_target = -1.0
		(_sfx["explosion"] as AudioStreamPlayer).stop()
		_set_drive_audio_muted(false)
	_flash = 1.0
	_env_section = 0
	env_director.apply(env_director.forest, 0.0)
	flow.enter_base()


func clear_section_time() -> void:
	_time_label.text = ""
	_timing_section = -1
	_prev_main_s = -1.0


# ───────────────────────── 区段环境 ─────────────────────────

var _env_section := 0

## 主赛道上按所在区段切环境（越过区段起点线时 2 秒过渡）；出库路、环道、车库外都是森林。
func _update_environment() -> void:
	var want := 0
	if car.path_id == Track.PATH_MAIN:
		want = track.section_index_at(car.s)
	if want != _env_section:
		_env_section = want
		env_director.transition_to(env_director.profile_for_section(want), _section_heading(want))
	cockpit.set_light(env_director.light_color, 1.0)


## 光向参照的车头方向：森林用出库方向（正北），其余用该区段起点线处的车头方向（8.2）。
func _section_heading(index: int) -> float:
	if index == 0:
		return 0.0
	var f := -track.transform_at(Track.PATH_MAIN, track.section_start[index]).basis.z
	return atan2(f.x, -f.z)


# ───────────────────────── 区段计时 ─────────────────────────

func _update_section_timer(delta: float) -> void:
	if car.path_id != Track.PATH_MAIN:
		_timing_section = -1
		_prev_main_s = -1.0
		return
	if _timing_section >= 0:
		_section_time += delta           # 失败演出和复位的时间也算在内
	var s := car.s
	if _prev_main_s >= 0.0 and s > _prev_main_s:
		for i in track.gate_s.size():
			var gate: float = track.gate_s[i]
			if _prev_main_s < gate and s >= gate:
				if _timing_section == i - 1 and i >= 1:
					flow.section_done(i - 1, _section_time)
				_timing_section = i if i < track.gate_s.size() - 1 else -1
				_section_time = 0.0
	_prev_main_s = s


static func _format_time(seconds: float) -> String:
	var whole := int(seconds)
	return "%d:%02d.%02d" % [whole / 60, whole % 60, int((seconds - whole) * 100.0)]


# ───────────────────────── 驶出开关（R-41，临时：标志牌和提示音在阶段 5） ─────────────────────────

## 车到岔路口还有多远（只在出库路和环道上有意义）。
func _distance_to_fork() -> float:
	if car.path_id == Track.PATH_ACCESS:
		return track.length(Track.PATH_ACCESS) - car.s + track.fork_s
	if car.s < track.fork_s:
		return track.fork_s - car.s
	return track.length(Track.PATH_LOOP) - car.s + track.fork_s


# ───────────────────────── 失败演出 ─────────────────────────

func _on_car_failed(kind: int) -> void:
	if _fail_phase != FailPhase.NONE:
		return
	_fail_kind = kind
	_fail_speed = car.v
	_fail_phase = FailPhase.PRE
	_fail_time = 0.0
	if kind == CarSim.Fail.OFF_TRACK:
		# 失败 1：车已经滑到路边那排方块上了，立刻撞击、爆炸（滑出去的过程发生在失败之前）
		car.mode = CarSim.Mode.LOCKED
		_fail_pre_time = 0.0
	else:
		# 失败 2 / 3：指针打到尽头卡住，换挡提示灯常亮，座舱闪一帧朱红，爆响；车还在赛道上
		car.mode = CarSim.Mode.COASTING
		cockpit.blown = true
		if kind == CarSim.Fail.DOWNSHIFT:
			# 失败 3：先听到转速被拉上去（轰一脚油）、冲过红线断油"嘟嘟嘟"，然后才爆
			_fail_pre_time = FAIL_DOWNSHIFT_PRE_TIME
			engine_audio.rev_target = Tuning.d.t12_blow_rpm
		else:
			# 失败 2：断油声已经响了一阵，直接爆响，0.4 秒后大爆炸
			_fail_pre_time = FAIL_PRE_TIME
			_red_frames = 1


func _update_fail_sequence(delta: float) -> void:
	if _fail_phase == FailPhase.NONE:
		return
	var t := Tuning.d
	_fail_time += delta
	if _fail_phase == FailPhase.PRE and _fail_time >= _fail_pre_time:
		_fail_phase = FailPhase.BOOM
		car.mode = CarSim.Mode.LOCKED
		_white_frames = WHITE_FRAMES
		explosion.play()
		if _fail_kind == CarSim.Fail.OFF_TRACK:
			_play_sfx("crash")
		elif _fail_kind == CarSim.Fail.DOWNSHIFT:
			_red_frames = 1
		_play_sfx("explosion")
		_set_drive_audio_muted(true)   # 10.5：爆炸播放时引擎、轮胎静音
	elif _fail_phase == FailPhase.BOOM:
		var boom_time := _fail_time - _fail_pre_time
		var skip := boom_time >= t.t51_skip_after and Input.is_action_just_pressed("throttle")
		if boom_time >= t.t51_explosion_time or skip:
			_finish_fail()


## 演出结束：原地复位（R-24），白闪一下。
func _finish_fail() -> void:
	_fail_phase = FailPhase.NONE
	explosion.stop()
	camera_rig.stop_flyoff()
	cockpit.blown = false
	engine_audio.rev_target = -1.0
	(_sfx["explosion"] as AudioStreamPlayer).stop()
	_set_drive_audio_muted(false)
	_recover_in_place()
	_flash = 1.0


func _play_sfx(sfx_name: String) -> void:
	var player := _sfx.get(sfx_name) as AudioStreamPlayer
	if player != null and player.stream != null:
		player.play()


func _set_drive_audio_muted(muted: bool) -> void:
	for bus: String in ["Engine", "Tires"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), muted)


## 9.5：小地图每帧按座舱里的锚点重新定位和缩放，所以始终贴着方向盘上缘。
func _place_minimap() -> void:
	var anchor := cockpit.minimap_anchor.global_position
	if cockpit_camera.is_position_behind(anchor):
		minimap_rect.visible = false
		return
	minimap_rect.visible = true
	var to_screen := Vector2(get_viewport().get_visible_rect().size) / Vector2(cockpit_viewport.size)
	var right := cockpit_camera.global_transform.basis.x * (MINIMAP_VIEW_WIDTH * 0.5)
	var center := cockpit_camera.unproject_position(anchor)
	var half_w := absf(cockpit_camera.unproject_position(anchor + right).x - center.x)
	var w := half_w * 2.0
	var h := w * float(Minimap.MAP_SIZE.y) / float(Minimap.MAP_SIZE.x)
	var top_left := Vector2(center.x - half_w, center.y - h * MINIMAP_ANCHOR_V)
	minimap_rect.position = top_left * to_screen
	minimap_rect.size = Vector2(w, h) * to_screen
	minimap_rect.material.set("shader_parameter/game_time", minimap.game_time)


## R-24：原地恢复（主赛道上暂时也一样）。
func _recover_in_place() -> void:
	var t := Tuning.d
	var v := t.t55_recover_min_kmh * CarSim.KMH
	var s_new := _recover_point()
	var arc := track.next_arc(car.path_id, s_new, car.exit_armed)
	if arc["found"]:
		var arc_limit := sqrt(t.t20_grip_g * CarSim.G * float(arc["radius"]))
		v = maxf(v, t.t55_recover_limit_factor * arc_limit)
	# T-55 只规定了环道上的恢复车速；在主赛道的长直道上它会比失败前还快，
	# 所以临时加一条：复位后的车速不超过失败那一刻的车速。
	v = minf(v, maxf(_fail_speed, t.t55_recover_min_kmh * CarSim.KMH))
	var gear := t.t01_gear_count
	for g in range(1, t.t01_gear_count + 1):
		var r := car.rpm_for(v, g)
		if r >= RECOVER_RPM_MIN and r <= RECOVER_RPM_MAX:
			gear = g
			break
	car.place(car.path_id, s_new, v, gear, car.from_access)


## 复位点：从出事的位置往回退出这个弯，再往回 recover_back_m；落点如果又在另一个弯里，再退出那个弯。
## 这样复位后前面有一段直道可以准备，而不是直接回到出事的弯里。
func _recover_point() -> float:
	var s := car.s
	for pass_i in 2:
		var walked := 0.0
		while walked < 800.0 and absf(track.curvature_at(car.path_id, s, car.exit_armed, car.from_access)) > 0.0005:
			s = _step_back(s, 5.0)
			walked += 5.0
		if pass_i == 0:
			s = _step_back(s, Tuning.d.recover_back_m)
	return s


func _step_back(s: float, d: float) -> float:
	if car.path_id == Track.PATH_LOOP and not car.from_access:
		return fposmod(s - d, track.length(Track.PATH_LOOP))
	return maxf(0.0, s - d)


## F4（暂时是瞬移）：放到下一个区段起点线，用 T-54 的车速和档位；城市之后回到森林。
func _jump_to_next_section() -> void:
	var t := Tuning.d
	var next := 0
	if car.path_id == Track.PATH_MAIN:
		next = (track.section_index_at(car.s) + 1) % track.section_names.size()
	# 放在区段起点线前 1 m，这样过线时计时正常开始
	car.place(Track.PATH_MAIN, maxf(track.gate_s[next] - 1.0, 0.0),
			t.t54_entry_speed_kmh[next] * CarSim.KMH, t.t54_entry_gear[next])
	_timing_section = -1
	_prev_main_s = -1.0


## 第 12 节阶段 2：路两侧的彩色测试方块（阶段 9 删除）。
## 离任何一条赛道中心线不足 TEST_CUBE_CLEAR 的不放；附近有方向不同的另一条路（岔路口、并入口）时，
## 离那条路不足 TEST_CUBE_JUNCTION_CLEAR 的也不放。
func _spawn_test_cubes() -> void:
	# 先把所有中心线采样点（位置 + 方向）放进网格，方便查"附近有没有路"
	var cell := TEST_CUBE_JUNCTION_CLEAR
	var grid: Dictionary = {}
	for p in 3:
		var s := 0.0
		while s <= track.length(p):
			var xf := track.transform_at(p, s)
			var c := xf.origin
			var d := -xf.basis.z
			var key := Vector2i(floori(c.x / cell), floori(c.z / cell))
			if not grid.has(key):
				grid[key] = []
			# 注意：这里必须用 Array。PackedArray 经 `as` 转型后 append 改的是副本，网格会一直是空的
			# （之前"方块不压路面"的检查因此从来没有生效过）。
			(grid[key] as Array).append([Vector2(c.x, c.z), Vector2(d.x, d.z).normalized(), p, s])
			s += 2.0
	var xforms: Array[Transform3D] = []
	var index := 0
	for p in 3:
		var s := float(TEST_CUBE_STEP)
		while s < track.length(p):
			var xf := track.transform_at(p, s)
			var c := xf.origin
			var fwd := -xf.basis.z
			var r := track.right_at(p, s)
			for side: float in [-1.0, 1.0]:
				index += 1
				var tall: float = TEST_CUBE_HEIGHTS[(index / 2) % TEST_CUBE_HEIGHTS.size()]
				var pos := c + r * side * TEST_CUBE_OFFSET + Vector3.UP * TEST_CUBE_SIZE * 0.5 * tall
				if _near_road(grid, cell, Vector2(pos.x, pos.z), Vector2(fwd.x, fwd.z).normalized(), p, s):
					continue
				xforms.append(Transform3D(Basis.from_scale(Vector3(1.0, tall, 1.0)), pos))
				_cube_colors.append(TEST_CUBE_COLORS[(index / 2) % TEST_CUBE_COLORS.size()])
			s += TEST_CUBE_STEP
	var box := BoxMesh.new()
	box.size = Vector3.ONE * TEST_CUBE_SIZE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, _cube_colors[i])
	var node := MultiMeshInstance3D.new()
	node.name = "TestCubes"
	node.multimesh = mm
	node.material_override = env_director.world_material
	track.add_child(node)


## point 处的方块（属于路径 path 的里程 at_s，那里路的方向是 dir）是否离某条路太近。
## "另一条路"指别的路径，或同一条路径上沿路相隔 TEST_CUBE_SAME_ROAD 以上的部分；
## 同一个弯自己的前后段不算，否则急弯两侧的方块会被全部清掉。
func _near_road(grid: Dictionary, cell: float, point: Vector2, dir: Vector2, path: int, at_s: float) -> bool:
	var base := Vector2i(floori(point.x / cell), floori(point.y / cell))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := base + Vector2i(dx, dy)
			if not grid.has(key):
				continue
			for q: Array in grid[key]:
				var dist := (q[0] as Vector2).distance_to(point)
				if dist < TEST_CUBE_CLEAR:
					return true
				if dist >= TEST_CUBE_JUNCTION_CLEAR:
					continue
				if int(q[2]) == path and absf(float(q[3]) - at_s) < TEST_CUBE_SAME_ROAD:
					continue
				if absf((q[1] as Vector2).dot(dir)) < TEST_CUBE_PARALLEL_DOT:
					return true
	return false
