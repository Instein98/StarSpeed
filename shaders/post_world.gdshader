shader_type spatial;
// 世界后处理（规格 8.3 第 2、4 条，8.5 V-02 / V-03，11.2）：
// 雾 → 径向拉线 → 线化（方案 A / B）→ 描边 → 压色板加抖动（含两套色板之间的抖动溶解）。
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

// 色板（sRGB 数值）；dissolve 从 0 到 1 时按抖动阈值从 palette_a 溶解到 palette_b
uniform vec3 palette_a[16];
uniform vec3 palette_b[16];
uniform float dissolve = 0.0;

// 雾（8.2）：1500 m 起，3500 m 完全变成雾色；深度 ≥ 3600 m 的像素不加雾
uniform vec3 fog_color = vec3(0.97, 0.93, 0.83);   // sRGB 数值
uniform float fog_start = 1500.0;
uniform float fog_end = 3500.0;
uniform float fog_cutoff = 3600.0;

// 速度感（由 speed_fx.gd 每帧设置）
uniform vec2 vanish_uv = vec2(0.5, 0.5);   // 消失点
uniform float streak = 0.0;                // 径向拉线强度
uniform float clear_radius = 1.0;          // 清晰区半径（占画面半高）
uniform float line_strength = 0.0;         // 线化强度
uniform float line_flow = 0.0;             // 线化图案向外流过的距离（画面半高为单位，脚本累加）
uniform bool mode_b = false;               // 方案 B：只拉线，不做线化

// 运动拉线（方案 M，开发者 2026-11-14 试玩后要求）：没有清晰圈，也没有叠上去的线条。
// 每个像素按"它在曝光时间里实际会在屏幕上划过多远"被拉长：离得近、从身边掠过的景物拉成长线，
// 远处的路和天空基本不动。划过的比例 = 曝光时间里车走的距离 ÷ 该像素的深度。
uniform bool motion_mode = false;
uniform float motion_dist = 0.0;           // 车速 × 曝光时间（米）
uniform float motion_max = 0.6;            // 拉线长度上限（占该像素到运动中心距离的比例）

const vec3 OUTLINE = vec3(0.106, 0.133, 0.2);   // #1b2233
const float DEPTH_EDGE = 0.03;
const float SILHOUETTE_MAX = 300.0;
const float CREASE_MAX = 80.0;
const float CREASE_COS = 0.8192;                // cos 35°
const float CLEAR_FEATHER = 0.15;
const int STREAK_SAMPLES = 16;
const float LINE_STRIPS = 240.0;
const float LINE_PERIOD = 0.25;
const float LINE_BRIGHT_THRESHOLD = 0.65;
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

// 加了雾的画面颜色（sRGB）
vec3 scene(vec2 uv, mat4 inv_proj) {
	vec3 col = to_srgb(texture(screen_tex, uv).rgb);
	float z = -view_pos(uv, inv_proj).z;
	if (z < fog_cutoff) {
		col = mix(col, fog_color, clamp((z - fog_start) / (fog_end - fog_start), 0.0, 1.0));
	}
	return col;
}

// 中心像素比"两侧邻居按平面推算出的深度"近 3% 以上，就是轮廓（画在近的一侧，1 像素宽）
float edge_pair(float zc, float za, float zb) {
	float pred = 2.0 / (1.0 / za + 1.0 / zb);
	return step(zc * (1.0 + DEPTH_EDGE), pred);
}

// 由深度重建的法线：每个方向取深度更连续的那一侧邻居
vec3 normal_at(vec2 uv, vec2 px, mat4 inv_proj) {
	vec3 c = view_pos(uv, inv_proj);
	vec3 l = view_pos(uv - vec2(px.x, 0.0), inv_proj);
	vec3 r = view_pos(uv + vec2(px.x, 0.0), inv_proj);
	vec3 u = view_pos(uv - vec2(0.0, px.y), inv_proj);
	vec3 d = view_pos(uv + vec2(0.0, px.y), inv_proj);
	vec3 dx = abs(r.z - c.z) < abs(c.z - l.z) ? r - c : c - l;
	vec3 dy = abs(d.z - c.z) < abs(c.z - u.z) ? d - c : c - u;
	return normalize(cross(dx, dy));
}

float motion_fraction(vec2 uv, mat4 inv_proj) {
	float z = -view_pos(uv, inv_proj).z;
	return min(motion_dist / max(z, 0.5), motion_max);
}

const int MOTION_PROBES = 8;
const int MOTION_SAMPLES = 16;
const float MOTION_PROBE_T[8] = float[8](-0.28, -0.16, -0.08, -0.03, 0.03, 0.08, 0.16, 0.28);

// 沿"指向运动中心"的方向收集会划过本像素的景物。q = 本像素相对运动中心的偏移。
// 位于 q × (1 + t) 的景物在曝光时间里会划过 |t| ÷ (1 + t) ≤ 比例 ÷ 2 的范围。
vec3 motion_streak(vec2 uv, vec2 center, mat4 inv_proj, out float amount) {
	vec2 q = uv - center;
	float f_self = motion_fraction(uv, inv_proj);
	float range = f_self;
	for (int i = 0; i < MOTION_PROBES; i++) {
		float t = MOTION_PROBE_T[i] * motion_max / 0.6;
		vec2 p = center + q * (1.0 + t);
		if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) {
			continue;
		}
		float f = motion_fraction(p, inv_proj);
		if (abs(t) / (1.0 + t) <= f * 0.5) {
			range = max(range, f);
		}
	}
	amount = range;
	vec3 sum = scene(uv, inv_proj);
	float weight = 1.0;
	if (range > 0.002) {
		float step_t = range / float(MOTION_SAMPLES);
		for (int i = 0; i < MOTION_SAMPLES; i++) {
			float t = (float(i) + 0.5) / float(MOTION_SAMPLES) * range - range * 0.5;
			vec2 p = center + q * (1.0 + t);
			if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) {
				continue;
			}
			float f = motion_fraction(p, inv_proj);
			float w = clamp((f * 0.5 - abs(t) / (1.0 + t)) / step_t + 0.5, 0.0, 1.0);
			sum += scene(p, inv_proj) * w;
			weight += w;
		}
	}
	return sum / weight;
}

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

vec3 pick(vec3 c, bool use_b, int i) {
	return use_b ? palette_b[i] : palette_a[i];
}

vec3 quantize(vec3 c, ivec2 pix) {
	float threshold = (BAYER[(pix.y % 4) * 4 + (pix.x % 4)] + 0.5) / 16.0;
	bool use_b = dissolve > threshold;
	int ia = 0;
	int ib = 1;
	float da = 1e9;
	float db = 1e9;
	for (int i = 0; i < 16; i++) {
		vec3 d = c - pick(c, use_b, i);
		float dist = dot(d, d);
		if (dist < da) {
			db = da; ib = ia; da = dist; ia = i;
		} else if (dist < db) {
			db = dist; ib = i;
		}
	}
	vec3 a = pick(c, use_b, ia);
	vec3 ab = pick(c, use_b, ib) - a;
	float t = clamp(dot(c - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 0.5);
	return (t * 2.0 > threshold) ? a + ab : a;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;

	// 到消失点的距离，以画面半高为单位
	vec2 to_center = vanish_uv - uv;
	vec2 d = -to_center * vec2(aspect, 1.0) * 2.0;
	float r = length(d);
	float outside = smoothstep(clear_radius, clear_radius + CLEAR_FEATHER, r);

	// 雾 + V-02 径向拉线
	vec3 col;
	float local_streak = streak * outside;
	float motion_amount = 0.0;
	if (motion_mode) {
		local_streak = 0.0;
		col = motion_streak(uv, vanish_uv, INV_PROJECTION_MATRIX, motion_amount);
	} else if (local_streak > 0.0005) {
		col = vec3(0.0);
		for (int i = 0; i < STREAK_SAMPLES; i++) {
			float f = float(i) / float(STREAK_SAMPLES - 1);
			col += scene(uv + to_center * local_streak * f, INV_PROJECTION_MATRIX);
		}
		col /= float(STREAK_SAMPLES);
	} else {
		col = scene(uv, INV_PROJECTION_MATRIX);
	}

	// V-03 线化（方案 B 跳过）
	float local_line = (mode_b || motion_mode) ? 0.0 : line_strength * outside;
	if (local_line > 0.0005) {
		float strip = floor((atan(d.y, d.x) / TAU + 0.5) * LINE_STRIPS);
		float value = hash(strip);
		float phase = fract((r - line_flow) / LINE_PERIOD + hash(strip + 311.0));
		bool bright = value > LINE_BRIGHT_THRESHOLD && phase < 0.7;
		if (bright) {
			col *= 1.0 + 0.3 * local_line;
		} else {
			col = mix(col, OUTLINE, 0.85 * local_line);
		}
	}

	// 描边
	vec3 pc = view_pos(uv, INV_PROJECTION_MATRIX);
	float zc = -pc.z;
	float edge = 0.0;
	if (zc < SILHOUETTE_MAX) {
		float zl = -view_pos(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX).z;
		float zr = -view_pos(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX).z;
		float zu = -view_pos(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX).z;
		float zd = -view_pos(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX).z;
		edge = max(edge_pair(zc, zl, zr), edge_pair(zc, zu, zd));
		if (edge < 0.5 && zc < CREASE_MAX) {
			vec3 n = normal_at(uv, px, INV_PROJECTION_MATRIX);
			// 只和右、下两个邻居比，折边 1 像素宽；邻居明显更近（是另一个物体的轮廓）时不算
			if (zr > zc * (1.0 - DEPTH_EDGE) && dot(n, normal_at(uv + vec2(px.x, 0.0), px, INV_PROJECTION_MATRIX)) < CREASE_COS) {
				edge = 1.0;
			} else if (zd > zc * (1.0 - DEPTH_EDGE) && dot(n, normal_at(uv + vec2(0.0, px.y), px, INV_PROJECTION_MATRIX)) < CREASE_COS) {
				edge = 1.0;
			}
		}
	}
	// 清晰区以外的描边随拉线 / 线化变淡
	edge *= 1.0 - clamp(max(max(local_streak, local_line), motion_amount * 6.0), 0.0, 1.0);
	col = mix(col, OUTLINE, edge);

	ALBEDO = to_linear(quantize(clamp(col, 0.0, 1.0), ivec2(FRAGCOORD.xy)));
}
