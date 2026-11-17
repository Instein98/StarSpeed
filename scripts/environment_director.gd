class_name EnvironmentDirector
extends Node
## 环境配置的应用（规格 8.2、8.3、11.2、11.4）。
## 森林、冰原、城市三套配置；越过区段起点线时 2 秒过渡：天空、雾、光线性过渡，色板按抖动阈值溶解（8.2）。
## 金牌版环境还没做。

const FLAT2TONE := preload("res://shaders/flat2tone.gdshader")
const SKY_SHADER := preload("res://shaders/sky_gradient.gdshader")

@export var forest: EnvironmentProfile
var ice: EnvironmentProfile
var city: EnvironmentProfile

const TRANSITION_TIME := 2.0

## 当前用的配置，和过渡中此刻的光色（座舱的光色跟着它，8.2）
var current: EnvironmentProfile
var light_color := Color.WHITE

var _from := {}
var _to := {}
var _t := 1.0

## 所有世界模型共用的两级明暗材质
var world_material: ShaderMaterial
## 世界后处理材质（由 main.gd 接到 WorldPost 上）
var post_material: ShaderMaterial

var _sky_material: ShaderMaterial


func _ready() -> void:
	ice = load("res://data/env_ice.tres") as EnvironmentProfile
	city = load("res://data/env_city.tres") as EnvironmentProfile
	assert(ice != null and city != null, "冰原 / 城市环境配置读不到")


func _init() -> void:
	world_material = ShaderMaterial.new()
	world_material.shader = FLAT2TONE
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER


## 建好 WorldEnvironment 的天空，并应用起始环境。heading_yaw = 光向所参照的车头方向（弧度，0 = 朝北）。
func setup(world_env: WorldEnvironment, post: ShaderMaterial) -> void:
	post_material = post
	var sky := Sky.new()
	sky.sky_material = _sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_env.environment = env
	apply(forest, 0.0)


## 第 index 个区段的配置（0 森林、1 冰原、2 城市）。
func profile_for_section(index: int) -> EnvironmentProfile:
	return [forest, ice, city][clampi(index, 0, 2)]


## 立即应用一个环境配置。
func apply(profile: EnvironmentProfile, heading_yaw: float) -> void:
	current = profile
	_t = 1.0
	var pal := _palette_vectors(profile.palette)
	post_material.set_shader_parameter("palette_a", pal)
	post_material.set_shader_parameter("palette_b", pal)
	post_material.set_shader_parameter("dissolve", 0.0)
	_set_values(_values(profile, heading_yaw))
	world_material.set_shader_parameter("brightness", profile.brightness)
	world_material.set_shader_parameter("night_emissive", _rgb(profile.night_emissive))
	world_material.set_shader_parameter("night_mode", profile.night_mode)


## 用 2 秒过渡到另一个环境配置。
func transition_to(profile: EnvironmentProfile, heading_yaw: float) -> void:
	if profile == current and _t >= 1.0:
		return
	_from = _values(current, 0.0) if _t >= 1.0 else _current_values()
	if _t >= 1.0:
		_from["light_dir"] = world_material.get_shader_parameter("light_dir")
	_to = _values(profile, heading_yaw)
	post_material.set_shader_parameter("palette_a", _palette_vectors(current.palette))
	post_material.set_shader_parameter("palette_b", _palette_vectors(profile.palette))
	post_material.set_shader_parameter("dissolve", 0.0)
	current = profile
	_t = 0.0


func _process(delta: float) -> void:
	if _t >= 1.0:
		return
	_t = minf(1.0, _t + delta / TRANSITION_TIME)
	_set_values(_current_values())
	post_material.set_shader_parameter("dissolve", _t)
	if _t >= 1.0:
		var pal := _palette_vectors(current.palette)
		post_material.set_shader_parameter("palette_a", pal)
		post_material.set_shader_parameter("dissolve", 0.0)


func _values(profile: EnvironmentProfile, heading_yaw: float) -> Dictionary:
	return {
		"fog": profile.fog_color, "top": profile.sky_top, "bottom": profile.sky_bottom,
		"light": profile.light_color, "light_dir": light_direction(profile, heading_yaw),
	}


func _current_values() -> Dictionary:
	var out := {}
	for k: String in _to:
		if _from[k] is Color:
			out[k] = (_from[k] as Color).lerp(_to[k], _t)
		else:
			out[k] = (_from[k] as Vector3).slerp(_to[k], _t)
	return out


func _set_values(v: Dictionary) -> void:
	light_color = v["light"]
	post_material.set_shader_parameter("fog_color", _rgb(v["fog"]))
	_sky_material.set_shader_parameter("sky_top", _rgb(v["top"]))
	_sky_material.set_shader_parameter("sky_bottom", _rgb(v["bottom"]))
	world_material.set_shader_parameter("light_dir", v["light_dir"])
	world_material.set_shader_parameter("light_color", _rgb(v["light"]))


## 指向光源的世界方向：光向相对车头给出，按区段起点线处的车头方向换算（8.2）。
static func light_direction(profile: EnvironmentProfile, heading_yaw: float) -> Vector3:
	var yaw := heading_yaw + deg_to_rad(profile.light_azimuth_deg)
	var el := deg_to_rad(profile.light_elevation_deg)
	return Vector3(sin(yaw) * cos(el), sin(el), -cos(yaw) * cos(el))


static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


static func _palette_vectors(colors: PackedColorArray) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in 16:
		var c := colors[mini(i, colors.size() - 1)]
		out.append(Vector3(c.r, c.g, c.b))
	return out
