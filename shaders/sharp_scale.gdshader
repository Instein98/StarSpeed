shader_type canvas_item;
// 锐利缩放（规格 8.1）：先最近邻放大整数倍、再线性缩小到屏幕尺寸。
// 贴图需用线性过滤采样；放大倍数正好是 prescale 时结果等于纯最近邻。

uniform float prescale = 3.0;

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * tex_size;
	vec2 cell = floor(px);
	vec2 c = fract(px) - 0.5;
	float region = 0.5 - 0.5 / prescale;
	vec2 offset = (c - clamp(c, vec2(-region), vec2(region))) * prescale + 0.5;
	COLOR = texture(TEXTURE, (cell + offset) / tex_size);
}
