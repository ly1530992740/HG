shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float pixel_block_size : hint_range(1.0, 4.0, 0.25) = 2.0;
uniform float color_levels : hint_range(8.0, 64.0, 1.0) = 24.0;
uniform float dither_strength : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float saturation : hint_range(0.5, 1.5, 0.01) = 0.88;
uniform float contrast : hint_range(0.5, 1.5, 0.01) = 1.05;
uniform float brightness_offset : hint_range(-0.2, 0.2, 0.005) = 0.025;

float bayer_4x4(vec2 coordinate) {
	ivec2 cell = ivec2(mod(floor(coordinate), 4.0));
	int index = cell.x + cell.y * 4;
	float matrix[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return matrix[index] / 16.0 - 0.5;
}

void fragment() {
	vec2 texture_size = vec2(textureSize(screen_texture, 0));
	vec2 snapped_pixel = floor(SCREEN_UV * texture_size / pixel_block_size) * pixel_block_size;
	vec2 snapped_uv = (snapped_pixel + vec2(pixel_block_size * 0.5)) / texture_size;
	vec3 color = textureLod(screen_texture, snapped_uv, 0.0).rgb;

	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luminance), color, saturation);
	color = (color - vec3(0.5)) * contrast + vec3(0.5 + brightness_offset);

	float dither = bayer_4x4(snapped_pixel / pixel_block_size) * dither_strength / color_levels;
	color = floor(clamp(color + vec3(dither), 0.0, 1.0) * color_levels + 0.5) / color_levels;
	COLOR = vec4(color, 1.0);
}
