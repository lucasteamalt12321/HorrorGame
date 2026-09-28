shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Monitor glass: samples the computer's SubViewport and adds CRT behaviour.
// All post effects are driven by uniforms so PHASE 21/22 can tune without
// touching scenes.

uniform sampler2D screen_texture : filter_nearest, repeat_disable;
uniform float power_on : hint_range(0.0, 1.0) = 1.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.22;
uniform float scanline_count : hint_range(20.0, 400.0) = 150.0;
uniform float curvature : hint_range(0.0, 0.5) = 0.06;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float brightness : hint_range(0.0, 3.0) = 1.25;
uniform float chroma_shift : hint_range(0.0, 0.02) = 0.0016;
uniform float noise_amount : hint_range(0.0, 0.3) = 0.035;
uniform float glitch_amount : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float t = TIME + time_offset;
	vec2 uv = UV;

	// Barrel-ish curvature.
	vec2 c = uv - vec2(0.5);
	float r2 = dot(c, c);
	uv = uv + c * r2 * curvature;

	// Rolling horizontal glitch bands.
	float band = step(0.995 - glitch_amount * 0.06, hash(vec2(floor(uv.y * 24.0), floor(t * 12.0))));
	float band_offset = band * glitch_amount * 0.05 * sin(t * 30.0);
	uv.x += band_offset;

	// Slight chromatic separation, stronger during glitches.
	float cs = chroma_shift * (1.0 + glitch_amount * 8.0);
	vec3 col;
	col.r = texture(screen_texture, clamp(uv + vec2(cs, 0.0), vec2(0.001), vec2(0.999))).r;
	col.g = texture(screen_texture, clamp(uv, vec2(0.001), vec2(0.999))).g;
	col.b = texture(screen_texture, clamp(uv - vec2(cs, 0.0), vec2(0.001), vec2(0.999))).b;

	// Scanlines.
	float scan = sin(uv.y * scanline_count) * 0.5 + 0.5;
	col *= mix(1.0, scan, scanline_strength);

	// Interlace noise.
	float n = noise(uv * vec2(320.0, 240.0) + vec2(t * 13.0, t * 7.0));
	col += (n - 0.5) * noise_amount;

	// Vignette + glass reflection sheen.
	float vig = 1.0 - vignette_strength * smoothstep(0.25, 0.95, length(c) * 1.5);
	col *= vig;
	float sheen = smoothstep(0.62, 0.0, distance(uv, vec2(0.28, 0.82))) * 0.05;
	col += sheen;

	// Power state: brown-out collapse to a bright horizontal line.
	if (power_on < 0.999) {
		float line = exp(-pow((uv.y - 0.5) * 90.0, 2.0));
		col = mix(col, vec3(line * 0.55, line * 0.6, line * 0.65), power_on);
	}

	ALBEDO = clamp(col * brightness, vec3(0.0), vec3(1.0));
	EMISSION = clamp(col * brightness * 1.35, vec3(0.0), vec3(4.0));
}
