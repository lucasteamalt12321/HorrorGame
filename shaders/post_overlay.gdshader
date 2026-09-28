shader_type canvas_item;
render_mode blend_mix;

// Post overlay for the 3D view: film grain, scanlines, vignette and the
// "the picture is not a picture" distortion used by the meta-horror beats.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float grain_enabled : hint_range(0.0, 1.0) = 1.0;
uniform float grain_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float scanline_enabled : hint_range(0.0, 1.0) = 1.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.12;
uniform float vignette_strength : hint_range(0.0, 1.5) = 0.55;
uniform float distortion : hint_range(0.0, 1.0) = 0.0;
uniform float desaturation : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Rolling displacement when the boundary breaks.
	uv.x += sin(uv.y * 40.0 + TIME * 3.0) * distortion * 0.004;
	uv.y += cos(uv.x * 33.0 + TIME * 2.2) * distortion * 0.003;

	vec4 src = texture(screen_tex, uv);

	float g = hash(uv * 1024.0 + vec2(TIME * 37.0, TIME * 71.0)) - 0.5;
	src.rgb += g * grain_intensity * 0.12 * grain_enabled;

	float scan = sin(uv.y * 900.0) * 0.5 + 0.5;
	src.rgb *= mix(1.0, scan, scanline_intensity * scanline_enabled);

	float d = distance(uv, vec2(0.5));
	src.rgb *= 1.0 - vignette_strength * smoothstep(0.32, 0.85, d);

	float l = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	src.rgb = mix(src.rgb, vec3(l), desaturation);

	src.rgb += tint.rgb * pulse;

	COLOR = src;
}
