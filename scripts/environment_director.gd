class_name EnvironmentDirector
extends Node
## 环境配置的应用（规格 8.2、8.3、11.2、11.4）。
## 阶段 2：只应用森林配置。按位置和金牌状态切换、2 秒过渡、色板溶解在阶段 5 / 10 补全。

const FLAT2TONE := preload("res://shaders/flat2tone.gdshader")
const SKY_SHADER := preload("res://shaders/sky_gradient.gdshader")

@export var forest: EnvironmentProfile

## 所有世界模型共用的两级明暗材质
var world_material: ShaderMaterial
## 世界后处理材质（由 main.gd 接到 WorldPost 上）
var post_material: ShaderMaterial

var _sky_material: ShaderMaterial


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


## 立即应用一个环境配置。
func apply(profile: EnvironmentProfile, heading_yaw: float) -> void:
	var pal := _palette_vectors(profile.palette)
	post_material.set_shader_parameter("palette_a", pal)
	post_material.set_shader_parameter("palette_b", pal)
	post_material.set_shader_parameter("dissolve", 0.0)
	post_material.set_shader_parameter("fog_color", _rgb(profile.fog_color))
	_sky_material.set_shader_parameter("sky_top", _rgb(profile.sky_top))
	_sky_material.set_shader_parameter("sky_bottom", _rgb(profile.sky_bottom))
	world_material.set_shader_parameter("light_dir", light_direction(profile, heading_yaw))
	world_material.set_shader_parameter("light_color", _rgb(profile.light_color))
	world_material.set_shader_parameter("brightness", profile.brightness)
	world_material.set_shader_parameter("night_emissive", _rgb(profile.night_emissive))
	world_material.set_shader_parameter("night_mode", profile.night_mode)


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
