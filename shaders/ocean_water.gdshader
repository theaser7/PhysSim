shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float sim_time = 0.0;
uniform float wave_amplitude_mult = 1.0;
uniform vec4 deep_color : source_color = vec4(0.02, 0.08, 0.18, 0.95);
uniform vec4 shallow_color : source_color = vec4(0.05, 0.45, 0.65, 0.85);
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.1;
uniform float roughness : hint_range(0.0, 1.0) = 0.08;

const float PI_2 = 6.28318530718;

// Harmonic wave vectors: (dir_deg, wavelength, amp_ratio, steepness)
const vec4 W1 = vec4(35.0, 26.0, 0.45, 0.40);
const vec4 W2 = vec4(80.0, 15.0, 0.28, 0.35);
const vec4 W3 = vec4(10.0, 8.0, 0.18, 0.30);
const vec4 W4 = vec4(-45.0, 4.0, 0.09, 0.25);

vec3 calculate_gerstner(vec4 wave, vec3 pos, float time, float g, inout vec3 normal) {
	float rad = radians(wave.x);
	vec2 d = normalize(vec2(sin(rad), cos(rad)));
	float k = PI_2 / wave.y;
	float omega = sqrt(g * k);
	float amp = wave.z * wave_amplitude_mult;
	float q = wave.w;
	float phi = k * dot(d, pos.xz) - (omega * time);

	float cos_phi = cos(phi);
	float sin_phi = sin(phi);

	// Displacement
	vec3 disp;
	disp.x = -(q / k) * d.x * amp * sin_phi;
	disp.y = amp * cos_phi;
	disp.z = -(q / k) * d.y * amp * sin_phi;

	// Normal contribution
	normal.x -= d.x * (amp * k) * sin_phi;
	normal.z -= d.y * (amp * k) * sin_phi;
	normal.y -= q * (amp * k) * cos_phi;

	return disp;
}

varying float wave_crest;
varying vec3 world_coord;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float g = 9.81;

	vec3 total_disp = vec3(0.0);
	vec3 calc_normal = vec3(0.0, 1.0, 0.0);

	total_disp += calculate_gerstner(W1, world_pos, sim_time, g, calc_normal);
	total_disp += calculate_gerstner(W2, world_pos, sim_time, g, calc_normal);
	total_disp += calculate_gerstner(W3, world_pos, sim_time, g, calc_normal);
	total_disp += calculate_gerstner(W4, world_pos, sim_time, g, calc_normal);

	VERTEX += total_disp;
	NORMAL = normalize(calc_normal);
	
	wave_crest = total_disp.y;
	world_coord = world_pos + total_disp;
}

void fragment() {
	// Fresnel factor
	float fresnel = sqrt(1.0 - dot(NORMAL, VIEW));
	fresnel = clamp(pow(fresnel, 3.0), 0.0, 1.0);

	// Depth color mixing based on wave height
	float height_factor = clamp((wave_crest + 0.5) / 1.5, 0.0, 1.0);
	vec4 base_water = mix(deep_color, shallow_color, height_factor);

	// Wave crest foam
	float foam_threshold = 0.45 * wave_amplitude_mult;
	float foam_mask = smoothstep(foam_threshold, foam_threshold + 0.25, wave_crest);
	
	// Micro-ripples using procedural sine combination
	float ripple = sin(world_coord.x * 4.0 + sim_time * 3.0) * cos(world_coord.z * 4.0 + sim_time * 2.5);
	foam_mask += clamp(ripple * 0.15 * foam_mask, 0.0, 1.0);

	vec3 final_color = mix(base_water.rgb, foam_color.rgb, foam_mask);
	final_color = mix(final_color, vec3(0.7, 0.85, 0.95), fresnel * 0.4);

	ALBEDO = final_color;
	METALLIC = metallic;
	ROUGHNESS = mix(roughness, 0.7, foam_mask);
	SPECULAR = 0.6;
}
