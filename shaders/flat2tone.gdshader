shader_type spatial;
// 两级明暗（规格 8.3 第 1 条、11.2）：输出 = 顶点色 × 光色 × 明暗系数 × 亮度。
// 不用引擎灯光；面法线由位置的屏幕空间导数求得，保证平直着色。
// 顶点色 alpha：1 = 普通；0 = 自发光；0.5 = 颜色由外部传入；0.25 = 夜间自发光。
render_mode unshaded, cull_disabled;

uniform vec3 light_dir = vec3(0.0, 1.0, 0.0);      // 世界空间里指向光源的方向
uniform vec3 light_color = vec3(1.0);              // sRGB 数值
uniform float brightness = 1.0;
uniform vec3 night_emissive = vec3(1.0);           // sRGB 数值
uniform bool night_mode = false;
uniform vec3 external_color = vec3(1.0);           // sRGB 数值
uniform bool use_instance_custom = false;          // 外部颜色取自 MultiMesh 自定义数据

varying vec3 world_pos;
varying vec4 vcol;
varying vec3 ext_col;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR;
	ext_col = use_instance_custom ? INSTANCE_CUSTOM.rgb : external_color;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
	if (dot(n, CAMERA_POSITION_WORLD - world_pos) < 0.0) {
		n = -n;
	}
	float a = vcol.a;
	vec3 base = vcol.rgb;
	if (a > 0.375 && a < 0.625) {
		base = ext_col;
	}
	vec3 srgb;
	if (a < 0.125) {
		srgb = base;
	} else if (night_mode && a < 0.375) {
		srgb = night_emissive;
	} else {
		float shade = dot(n, normalize(light_dir)) > 0.15 ? 1.0 : 0.72;
		srgb = base * light_color * shade * brightness;
	}
	ALBEDO = to_linear(clamp(srgb, 0.0, 1.0));
}
