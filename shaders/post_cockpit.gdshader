shader_type spatial;
// 座舱后处理（规格 8.3 第 3、4 条，11.2a）：轮廓描边 → 压座舱色板加抖动。
// 深度等于远裁剪面的像素（窗外）输出 alpha = 0，不画描边。
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

const vec3 OUTLINE = vec3(0.106, 0.133, 0.2);   // #1b2233
const float DEPTH_EDGE = 0.03;

// 座舱独立 16 色色板（8.2），sRGB 数值
const vec3 PALETTE[16] = vec3[16](
	vec3(0.106, 0.133, 0.200), vec3(0.059, 0.078, 0.141), vec3(0.169, 0.208, 0.314), vec3(0.227, 0.255, 0.314),
	vec3(0.290, 0.322, 0.384), vec3(0.541, 0.576, 0.639), vec3(0.937, 0.290, 0.184), vec3(0.710, 0.216, 0.122),
	vec3(1.000, 0.788, 0.235), vec3(0.969, 0.925, 0.831), vec3(1.000, 1.000, 1.000), vec3(0.851, 0.804, 0.706),
	vec3(0.773, 0.478, 0.227), vec3(0.541, 0.310, 0.133), vec3(0.788, 0.820, 0.863), vec3(0.310, 0.722, 0.902));

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

// 中心像素比"两侧邻居按平面推算出的深度"近 3% 以上，就是轮廓（画在近的一侧，1 像素宽）
float edge_pair(float zc, float za, float zb) {
	float pred = 2.0 / (1.0 / za + 1.0 / zb);
	return step(zc * (1.0 + DEPTH_EDGE), pred);
}

vec3 quantize(vec3 c, ivec2 pix) {
	int ia = 0;
	int ib = 1;
	float da = 1e9;
	float db = 1e9;
	for (int i = 0; i < 16; i++) {
		vec3 d = c - PALETTE[i];
		float dist = dot(d, d);
		if (dist < da) {
			db = da; ib = ia; da = dist; ia = i;
		} else if (dist < db) {
			db = dist; ib = i;
		}
	}
	vec3 a = PALETTE[ia];
	vec3 ab = PALETTE[ib] - a;
	float t = clamp(dot(c - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 0.5);
	float threshold = (BAYER[(pix.y % 4) * 4 + (pix.x % 4)] + 0.5) / 16.0;
	return (t * 2.0 > threshold) ? PALETTE[ib] : a;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float raw = texture(depth_tex, uv).r;
	if (raw <= 0.000001) {
		ALBEDO = vec3(0.0);
		ALPHA = 0.0;
	} else {
		vec2 px = 1.0 / VIEWPORT_SIZE;
		float zc = lin_depth(uv, INV_PROJECTION_MATRIX);
		float zl = lin_depth(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
		float zr = lin_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
		float zu = lin_depth(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
		float zd = lin_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
		float edge = max(edge_pair(zc, zl, zr), edge_pair(zc, zu, zd));
		vec3 col = to_srgb(texture(screen_tex, uv).rgb);
		col = mix(col, OUTLINE, edge);
		ALBEDO = to_linear(quantize(col, ivec2(FRAGCOORD.xy)));
		ALPHA = 1.0;
	}
}
