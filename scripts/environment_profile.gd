class_name EnvironmentProfile
extends Resource
## 一个环境的配置（规格 8.2、6.6、11.4）。颜色都是规格里写的 sRGB 色值。

@export var profile_name: String
@export var palette: PackedColorArray          ## 16 色色板
@export var sky_top: Color
@export var sky_bottom: Color
@export var fog_color: Color
## 光从哪来：相对车头方向的水平角（0 = 正前，正值偏右）和仰角
@export var light_azimuth_deg: float
@export var light_elevation_deg: float
@export var light_color: Color
@export var brightness: float = 1.0
@export var night_emissive: Color = Color.WHITE  ## 夜间自发光色（金牌版）
@export var night_mode: bool = false
@export var ground_color: Color
@export var cloud_count: int
@export var far_ring_variant: String             ## "a" 远山 / "b" 雪峰 / "c" 天际线
@export var gold_fx: String                      ## 氛围物："" / "meteor" / "aurora" / "neon"
