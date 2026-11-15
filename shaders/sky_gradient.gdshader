shader_type sky;
// 天空两色渐变（规格 8.2）：仰角 0° 及以下为下部色，35° 及以上为上部色，之间线性过渡。

uniform vec3 sky_top = vec3(0.31, 0.72, 0.9);       // sRGB 数值
uniform vec3 sky_bottom = vec3(0.97, 0.93, 0.83);   // sRGB 数值

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void sky() {
	float elevation = asin(clamp(EYEDIR.y, -1.0, 1.0));
	float t = clamp(elevation / radians(35.0), 0.0, 1.0);
	COLOR = to_linear(mix(sky_bottom, sky_top, t));
}
