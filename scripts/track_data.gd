class_name TrackData
extends Resource
## 一条路径：起点、朝向、分段数组（规格 6.2、6.4、6.5、11.4）。
## 各分段数组等长，下标一一对应。

@export var path_name: String
@export var start: Vector2                    ## 赛道平面坐标：x 向东，y 向北（米）
@export var heading_deg: float                ## 0 = 朝北，顺时针为正
@export var closed: bool

@export var seg_label: PackedStringArray      ## 规格里的编号，如 "F15"
@export var seg_type: PackedInt32Array        ## 0 = 直道，1 = 左弧，2 = 右弧
@export var seg_radius: PackedFloat32Array    ## 圆弧半径（直道为 0）
@export var seg_angle_deg: PackedFloat32Array ## 圆弧角度（直道为 0）；圆弧长度 = 半径 × 角度
@export var seg_length: PackedFloat32Array    ## 直道长度（圆弧为 0）
@export var seg_grade_pct: PackedFloat32Array ## 坡度 %

## 仅主赛道：区段名称，以及每个区段包含的分段数（区段线里程按各段精确长度累加得出）。
@export var section_names: PackedStringArray
@export var section_seg_counts: PackedInt32Array
