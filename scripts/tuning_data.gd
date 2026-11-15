class_name TuningData
extends Resource
## 调参表（规格第 7.2 节 T-xx 与第 7.3 节速度层级表）的全部字段。
## 数值只写在 data/tuning.tres 里；这里的字段没有默认值。
## 单位照规格书写：车速 km/h、减速度 g、比例用小数（6% = 0.06）、角度用度。

@export_group("引擎与传动")
@export var t01_gear_count: int
@export var t02_cut_speed_kmh: PackedFloat32Array        ## 各档断油车速
@export var t03_idle_rpm: float
@export var t04_redline_rpm: float
@export var t05_cut_rpm: float
@export var t06_best_shift_rpm: float
@export var t07_torque_curve: PackedVector2Array         ## (rpm, 系数) 折线
@export var t08_peak_accel: PackedFloat32Array           ## 各档峰值加速度 m/s²
@export var t09_upshift_time: float
@export var t10_downshift_time: float
@export var t11_overrev_limit: float
@export var t12_blow_rpm: float
@export var t13_coast_decel_g: float
@export var t13_coast_knee_rpm: float                    ## T-13/T-14 之间的拐点（规格初始 6000）
@export var t14_coast_decel_max_g: float
@export var t15_downshift_speed_loss: float
## 极速（开发者 2026-11-15：没有第 9 档，游戏里的最高车速是 8 档 8500 转 = 680 km/h）。
## 离极速不到 top_speed_taper_kmh 时驱动加速度线性减到 0。
@export var top_speed_kmh: float
@export var top_speed_taper_kmh: float
## 景物拉线随车速的增长方式：拉线长度 = 车速 × 曝光 × (车速 ÷ fx_motion_full_kmh) ^ fx_motion_power。
## power = 0 是线性；越大，中低速越接近没有、高速涨得越猛。
@export var fx_motion_full_kmh: float
@export var fx_motion_power: float
@export var brake_decel_g: float                         ## 刹车减速度（规格里没有刹车，开发者试玩后加的）
@export var t16_uphill_factor: float
@export var t17_downhill_factor: float
@export var t18_shift_lamp_rpm: float

@export_group("抓地")
@export var t20_grip_g: float
@export var t21_smooth_window_m: float
@export var t22_zone1_start: float
@export var t23_zone2_start: float
@export var t24_zone3_start: float
@export var t25_struggle_max: float
@export var t26_struggle_limit: float
@export var t27_slide_max_m: float
## 打滑（规格里没有，开发者试玩后加的；T-25、T-26、T-27 不再使用）
@export var slide_wall_m: float                          ## 车滑到离中心线多远算撞上路边
@export var slide_return_max_angle_deg: float            ## 回原路线时车头最多偏离赛道方向多少度（横向速度 ≤ 车速 × tan）
@export var slide_return_time: float                     ## 抓地力恢复后把车拉回原路线的时间常数（秒）
@export var recover_back_m: float                        ## 失败后的复位点：出事那个弯的入口再往回多少米

@export_group("镜头与速度感")
@export var t30_world_fov_curve: PackedVector2Array      ## (km/h, 垂直 FOV°)
@export var t31_fov_smooth_time: float
@export var t32_fov_pulse_deg: float
@export var t32_fov_pulse_time: float
@export var t33_pitch_back_deg: float
@export var t34_pitch_nod_deg: float
@export var t35_roll_deg: float
@export var t36_head_turn_max_deg: float
@export var t37_zone2_mm: float
@export var t37_zone3_mm: float
@export var t37_struggle_mm: float
@export var t37_struggle_roll_deg: float
@export var t37_limiter_mm: float                        ## 第 7.3 节事件表"进入断油：高频微震 3 mm"
@export var t37_freq_hz: float
@export var t38_struggle_yaw_deg: float                  ## 转向不足时头向弯内侧偏转的最大角度
@export var understeer_roll_deg: float                  ## 转向不足时头向弯内侧歪的最大角度
@export var understeer_edge_share: float                ## 刚到极限（ratio 100%）时用到上面两个角度的多少
@export var understeer_full_over: float                 ## ratio 超出 100% 多少时偏到最大
@export var understeer_smooth_time: float
@export var slide_return_yaw_gain: float                 ## 救回时车头偏角在画面上放大多少倍（1 = 真实角度）
@export var t39_head_turn_dist_m: float
@export var t39a_head_turn_speed_deg: float
@export var t40_star_enter_kmh: float
@export var t40_star_exit_kmh: float
@export var t41_vfx_smooth_time: float
@export var t44_fade_start_kmh: float
@export var t44_fade_full_kmh: float
@export var t45_world_resolution: Vector2i
@export var t46_cockpit_resolution: Vector2i
@export var t47_cockpit_fov_curve: PackedVector2Array    ## (km/h, 垂直 FOV°)
@export var t48_fx_mode: String                          ## "M" 运动拉线 / "A" / "B"（F5 轮换）
## 方案 M（不在规格里；开发者 2026-11-14 试玩后要求）：景物按掠过身边的快慢自然拉成线
@export var fx_motion_exposure: float                    ## 曝光时间（秒）：越大拉得越长
@export var fx_motion_max_span: float                    ## 拉线长度上限（占到运动中心距离的比例）

@export_group("流程")
@export var t50_ignition_hold: float
@export var t51_explosion_time: float
@export var t51_fade_time: float
@export var t51_skip_after: float
@export var t52_lookahead_seconds: float
@export var t52_lookahead_min_m: float
@export var t52_lookahead_max_m: float
@export var t53_forest_thresholds: PackedFloat32Array    ## 金 / 银 / 铜（秒）
@export var t53_ice_thresholds: PackedFloat32Array
@export var t53_city_thresholds: PackedFloat32Array
@export var t54_entry_speed_kmh: PackedFloat32Array      ## 森林 / 冰原 / 城市
@export var t54_entry_gear: PackedInt32Array
@export var t55_recover_min_kmh: float
@export var t55_recover_limit_factor: float
@export var t56_replay_time: float
@export var t57_tire_drive_factor: float
@export var t58_throttle_downshift_loss: float
@export var t59_downshift_lamp_rpm: float

@export_group("速度层级表（第 7.3 节）")
@export var fx_speed_kmh: PackedFloat32Array
@export var fx_streak: PackedFloat32Array                ## 径向拉线强度
@export var fx_clear_radius: PackedFloat32Array          ## 清晰区半径（占画面半高）
@export var fx_line: PackedFloat32Array                  ## 线化强度
@export var fx_shake_mm: PackedFloat32Array              ## 座舱震动幅度
@export var fx_wind: PackedFloat32Array                  ## 风声音量（线性）
