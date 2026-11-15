shader_type canvas_item;
// V-06 挣扎暗角（规格 8.5、11.2）：画面四边向内的朱红色抖动网点，
// 宽度 = 挣扎计时器 ÷ T-26 × 画面宽度的 15%；网点按 960×540 的像素网格对齐。

uniform float amount = 0.0;                 // 挣扎计时器 ÷ T-26
uniform vec2 grid = vec2(960.0, 540.0);
uniform float max_width = 0.15;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 p = floor(UV * grid);
	float width = amount * max_width * grid.x;
	float dist = min(min(p.x, grid.x - 1.0 - p.x), min(p.y, grid.y - 1.0 - p.y));
	float cover = width > 0.0 ? clamp(1.0 - dist / width, 0.0, 1.0) : 0.0;
	ivec2 ip = ivec2(p);
	float threshold = (BAYER[(ip.y % 4) * 4 + (ip.x % 4)] + 0.5) / 16.0;
	COLOR = vec4(0.937, 0.29, 0.184, cover > threshold ? 1.0 : 0.0);
}
