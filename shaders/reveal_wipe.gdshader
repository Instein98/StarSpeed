shader_type canvas_item;
// V-01 世界揭开（规格 8.5）：窗外从全黑变为可见。画面正中出现一条水平的暖白亮线，
// 0.35 秒内向上下两边推开；推开的边缘是 2 行抖动网点。按 960×540 的像素网格画。
// open = 0：全黑（open < 0 时连亮线也没有）；open = 1：完全揭开。

uniform float open = -1.0;
const vec2 GRID = vec2(960.0, 540.0);
const vec3 BLACK = vec3(0.0);
const vec3 WARM = vec3(0.969, 0.925, 0.831);

void fragment() {
	vec2 pix = floor(SCREEN_UV * GRID);
	float half_h = GRID.y * 0.5;
	float dy = abs(pix.y + 0.5 - half_h);
	if (open < 0.0) {
		COLOR = vec4(BLACK, 1.0);
	} else {
		float edge = open * half_h;
		if (dy < edge) {
			COLOR = vec4(0.0);
		} else if (dy < edge + 1.0) {
			COLOR = vec4(WARM, 1.0);                       // 推开的亮边
		} else if (dy < edge + 3.0) {
			bool on = mod(pix.x + pix.y, 2.0) < 1.0;        // 2 行抖动网点
			COLOR = on ? vec4(BLACK, 1.0) : vec4(WARM, 1.0);
		} else {
			COLOR = vec4(BLACK, 1.0);
		}
		if (open >= 1.0) {
			COLOR = vec4(0.0);
		}
	}
}
