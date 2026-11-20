extends Node
## 启动时把各节点互相连好；处理 F2 – F4（规格 11.4）。
## 临时写在这里、阶段 5 迁到 run_director.gd 的东西：R-24 原地恢复、F4 瞬移、跑完尾段回车库起点、
## 失败演出、驶出开关。

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
const RESTART_LEAD := 150.0
const TELEPORT_M := 200.0     ## 一帧移动超过这么多米算瞬移（第 5 轮 #3 回归测试时发现）   ## 重开 / 单区段：放在区段起点线前多少米

var _flash := 0.0
var _white_frames := 0
var _red_frames := 0
var _fail_phase := FailPhase.NONE
var _fail_kind := 0
var _fail_time := 0.0
var _fail_speed := 0.0
var _fail_pre_time := FAIL_PRE_TIME
var _sfx: Dictionary = {}
var scenery: Scenery
var sfx: Sfx
var tutorial: Tutorial
## 理想车速曲线（分层音乐按 车速 ÷ 理想车速 叠加鼓和主音）
var pace_profile: PaceProfile
## F6：分层音乐的调试灯
var music_lamps: MusicLamps
## 最好成绩的幽灵和实时差值
var ghost: Ghost
## 过弯评价
var corner_judge: CornerJudge
## 座舱亮度：点火前 0.15，点火演出里升到 1.0（8.2、8.3）
var cockpit_brightness := 1.0
var _minimap_on := true
var _ignited := true
## ≥ 0 时全屏白化到这个不透明度（结尾 6.7 第 1 步）
var whiteout := -1.0
var _reveal: ColorRect
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
	scenery = Scenery.new()
	scenery.name = "Scenery"
	track.add_child(scenery)
	scenery.build(track, env_director.world_material)
	for i in 3:
		scenery.set_gold_heading(i, rad_to_deg(_section_heading(i)))
	minimap_rect.texture = minimap.get_texture()
	cockpit.set_light(env_director.forest.light_color, 1.0)

	car.track = track
	car.auto_shift = bool(SaveData.data.get("auto_shift", false))
	SaveData.settings_applied.connect(func(): car.auto_shift = bool(SaveData.data.get("auto_shift", false)))
	pace_profile = PaceProfile.new()
	pace_profile.build(track)
	car.failed.connect(_on_car_failed)
	ghost = Ghost.new()
	ghost.name = "Ghost"
	world_viewport.add_child(ghost)
	ghost.setup(self, car, track)
	cockpit.car = car
	camera_rig.bind(car, track, cockpit_camera)
	world_post.bind(car, track)
	minimap.bind(car, track, cockpit)
	minimap.ghost = ghost
	engine_audio.car = car
	tire_audio.bind(car)
	overlay.set("car", car)
	overlay.set("track", track)
	overlay.visible = false
	var music := Music.new()
	music.name = "Music"
	music.main = self
	$Audio.add_child(music)
	music_lamps = MusicLamps.new()
	music_lamps.name = "MusicLamps"
	music_lamps.music = music
	music_lamps.visible = false
	$UI/UIRoot.add_child(music_lamps)
	var mix_panel := MixPanel.new()
	mix_panel.name = "MixPanel"
	mix_panel.engine = engine_audio
	mix_panel.tires = tire_audio
	$UI/UIRoot.add_child(mix_panel)
	sfx = Sfx.new()
	sfx.name = "Sfx"
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	$Audio.add_child(sfx)
	corner_judge = CornerJudge.new()
	corner_judge.name = "CornerJudge"
	add_child(corner_judge)
	corner_judge.setup(self, car)
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	add_child(tutorial)
	var world_audio := WorldAudio.new()
	world_audio.name = "WorldAudio"
	$Audio.add_child(world_audio)
	world_audio.setup(self, car)
	# V-01 世界揭开：盖在世界画面上、座舱画面下的一层
	_reveal = ColorRect.new()
	_reveal.name = "RevealWipe"
	_reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal.set_anchors_preset(Control.PRESET_FULL_RECT)
	var reveal_mat := ShaderMaterial.new()
	reveal_mat.shader = load("res://shaders/reveal_wipe.gdshader")
	_reveal.material = reveal_mat
	world_rect.get_parent().add_child(_reveal)
	world_rect.get_parent().move_child(_reveal, world_rect.get_index() + 1)
	# 打滑的朱红晕影放到座舱画面上面（原来在座舱下面，大部分被座舱挡住看不见）
	vignette.get_parent().move_child(vignette, cockpit_rect.get_index())
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
	tutorial.setup(self, car, flow)
	flow.enter_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_reload"):
		Tuning.reload()
		pace_profile.build(track)
	elif event.is_action_pressed("debug_overlay"):
		overlay.visible = not overlay.visible
	elif event.is_action_pressed("debug_next_segment"):
		if _fail_phase == FailPhase.NONE:
			set_ignited_look(true)
			_jump_to_next_section()
			flow.debug_enter_run()
	elif event.is_action_pressed("debug_music"):
		music_lamps.visible = not music_lamps.visible
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
	if whiteout >= 0.0:
		fullscreen_fade.color = Color(1.0, 1.0, 1.0, whiteout)
	elif _white_frames > 0:
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
	_cancel_fail()
	_reset_look()
	flow.enter_base()


## 一键重开计时赛（开发者 2026-11-19 第 1 轮 #1）：车放回主赛道起点（岔路口，森林起点线前 150 m），
## 用森林区段的进场车速和档位，计时从过起点线开始。暂停菜单"重新开始"或 R 键。
## section ≥ 0 = 单区段计时赛（第 2 轮 #3）：放到那个区段起点线前 150 m，用那个区段的进场车速和档位。
func restart_run(section := -1) -> void:
	_cancel_fail()
	_reset_look()
	var t := Tuning.d
	var i := maxi(section, 0)
	clear_section_time()
	car.use_device_input = true
	car.brake = false
	car.set_exit_armed(true)
	car.place(Track.PATH_MAIN, maxf(track.gate_s[i] - RESTART_LEAD, 0.0), t.t54_entry_speed_kmh[i] * CarSim.KMH, t.t54_entry_gear[i])
	car.mode = CarSim.Mode.DRIVE
	flow.restart_state(section)


func _cancel_fail() -> void:
	if _fail_phase != FailPhase.NONE:
		_fail_phase = FailPhase.NONE
		explosion.stop()
		camera_rig.stop_flyoff()
		cockpit.blown = false
		engine_audio.rev_target = -1.0
		(_sfx["explosion"] as AudioStreamPlayer).stop()
		_set_drive_audio_muted(not _ignited)


func _reset_look() -> void:
	_minimap_on = _ignited
	camera_rig.ending_look = 0.0
	cockpit.stickers.zoom = 1.0
	whiteout = -1.0
	_flash = 1.0
	_env_gold = false
	_env_section = 0
	env_director.apply(env_director.forest, 0.0)
	scenery.set_environment(0)


## 结尾（6.7 第 2 步）：白化结束后车停在车库里，世界画面正常显示。
func ending_in_garage() -> void:
	car.use_device_input = false
	car.set_throttle(false)
	car.brake = false
	car.place(Track.PATH_ACCESS, 0.0, 0.0, 1, true)
	car.mode = CarSim.Mode.LOCKED
	clear_section_time()
	_env_section = 0
	_env_gold = false
	env_director.apply(env_director.forest, 0.0)
	scenery.set_environment(0)
	_minimap_on = false
	whiteout = -1.0
	_flash = 1.0


## 回标题画面：和回大本营一样先收拾失败演出，然后进标题（窗外全黑）。
func return_to_title() -> void:
	return_to_base()
	flow.enter_title()


## 点火前后座舱和窗外的样子（6.8、8.3、9.4）。on = 已点火。
func set_ignited_look(on: bool) -> void:
	set_world_reveal(1.0 if on else -1.0)
	cockpit_brightness = 1.0 if on else 0.15
	cockpit.set_tach_brightness(1.0 if on else 0.3)
	cockpit.stickers_lit = not on
	cockpit.show_gear = on
	cockpit.needle_override = -1.0 if on else 0.0
	_minimap_on = on
	_ignited = on
	set_drive_audio_on(on)


func set_world_reveal(open: float) -> void:
	(_reveal.material as ShaderMaterial).set_shader_parameter("open", open)
	_reveal.visible = open < 1.0


func set_drive_audio_on(on: bool) -> void:
	_set_drive_audio_muted(not on)


func clear_section_time() -> void:
	_time_label.text = ""
	_timing_section = -1
	_prev_main_s = -1.0


# ───────────────────────── 区段环境 ─────────────────────────

var _env_section := 0
var _env_gold := false

## 主赛道上按所在区段切环境（越过区段起点线时 2 秒过渡）；出库路、环道、车库外都是森林。
func _update_environment() -> void:
	var want := 0
	var gold := false
	if car.path_id == Track.PATH_MAIN:
		want = track.section_index_at(car.s)
		gold = int((SaveData.data.get("best_medals", [0, 0, 0]) as Array)[want]) >= 4
	if car.path_id == Track.PATH_ACCESS and car.s < Track.GARAGE_DOOR_Y:
		want = -1      # 车库内
	if want != _env_section or gold != _env_gold:
		_env_section = want
		_env_gold = gold
		var profile := env_director.garage if want < 0 else env_director.profile_for_section(want, gold)
		env_director.transition_to(profile, _section_heading(maxi(want, 0)))
		scenery.set_environment(maxi(want, 0), gold)
	cockpit.set_light(env_director.light_color, cockpit_brightness)


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
	# 一个物理帧走了 TELEPORT_M 以上 = 瞬移（调试、测试脚本摆车），不是开过去的：取消这一段的计时，不记成绩和幽灵
	if _prev_main_s >= 0.0 and absf(s - _prev_main_s) > TELEPORT_M:
		_timing_section = -1
		_prev_main_s = s
		return
	if _prev_main_s >= 0.0 and s > _prev_main_s:
		for i in track.gate_s.size():
			var gate: float = track.gate_s[i]
			if _prev_main_s < gate and s >= gate:
				if _timing_section == i - 1 and i >= 1:
					flow.section_done(i - 1, _section_time)
					ghost.section_finished(i - 1, flow.section_records[i - 1])
				_timing_section = i if i < track.gate_s.size() - 1 else -1
				_section_time = 0.0
				if _timing_section >= 0:
					flow.section_banner(_timing_section)
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
		# 失败 1：车已经滑到路边的护栏上了，立刻撞击、爆炸（滑出去的过程发生在失败之前）
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
	for bus: String in ["Engine", "Tires", "Wind"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), muted)


## 9.5：小地图每帧按座舱里的锚点重新定位和缩放，所以始终贴着方向盘上缘。
func _place_minimap() -> void:
	var anchor := cockpit.minimap_anchor.global_position
	if not _minimap_on or cockpit_camera.is_position_behind(anchor):
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
