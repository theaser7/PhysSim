shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Blender-style photorealistic ocean water shader
// Preserves exact Gerstner displacement math for physics synchronization

uniform float sim_time = 0.0;
uniform float wave_amplitude_mult = 1.0;

// High-fidelity Blender ocean color palette
uniform vec4 deep_color : source_color = vec4(0.015, 0.075, 0.165, 0.96);
uniform vec4 shallow_color : source_color = vec4(0.04, 0.38, 0.55, 0.88);
uniform vec4 scatter_color : source_color = vec4(0.08, 0.68, 0.72, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.97, 1.0, 1.0);

uniform float metallic : hint_range(0.0, 1.0) = 0.04;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.45;
uniform float foam_threshold : hint_range(0.0, 2.0) = 0.32;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

const float PI_2 = 6.28318530718;

// Harmonic wave vectors: (dir_deg, wavelength, amp_ratio, steepness) - Synchronized with OceanSystem
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
varying vec3 vertex_normal;

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
	vertex_normal = normalize(calc_normal);
	NORMAL = vertex_normal;

	wave_crest = total_disp.y;
	world_coord = world_pos + total_disp;
}

void fragment() {
	// Micro-wave normal perturbation (multi-frequency animated ripples)
	vec2 p = world_coord.xz;
	float t = sim_time * 1.2;

	vec2 uv1 = p * 1.8 + vec2(t * 0.35, t * 0.25);
	vec2 uv2 = p * 4.2 - vec2(t * 0.45, -t * 0.30);
	vec2 uv3 = p * 8.5 + vec2(-t * 0.65, t * 0.50);

	float s1 = sin(uv1.x + cos(uv1.y * 1.2));
	float c1 = cos(uv1.y + sin(uv1.x * 0.8));
	float s2 = sin(uv2.x * 0.9 + uv2.y * 1.1);
	float c2 = cos(uv2.y * 0.9 - uv2.x * 1.1);
	float s3 = sin(uv3.x) * cos(uv3.y);

	vec3 wave_pert = vec3(
		-(c1 * 0.18 + s2 * 0.12 + s3 * 0.06),
		1.0,
		-(s1 * 0.18 + c2 * 0.12 + s3 * 0.06)
	);
	wave_pert = normalize(wave_pert);

	// Blend Gerstner macro normal with high-frequency micro normal
	vec3 perturbed_normal = normalize(mix(NORMAL, wave_pert, normal_strength));
	NORMAL = perturbed_normal;

	// View alignment & Fresnel reflection (Schlick IOR ~1.33)
	float n_dot_v = max(dot(NORMAL, VIEW), 0.0);
	float fresnel = 0.035 + (1.0 - 0.035) * pow(1.0 - n_dot_v, 4.5);

	// Depth buffer sampling for underwater absorption and contact foam
	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float linear_depth = -view_pos.z;
	float water_depth = max(linear_depth - (-VERTEX.z), 0.0);

	// Refraction offset based on surface normal
	vec2 refr_offset = NORMAL.xz * 0.025 * clamp(water_depth * 0.5, 0.1, 1.0);
	vec3 refracted_bg = textureLod(screen_texture, SCREEN_UV + refr_offset, 0.0).rgb;

	// Beer-Lambert light absorption
	float depth_factor = clamp(water_depth * 0.35, 0.0, 1.0);
	vec3 deep_mix = mix(shallow_color.rgb, deep_color.rgb, depth_factor);
	vec3 absorbed_water = mix(refracted_bg, deep_mix, clamp(depth_factor * 1.25, 0.35, 0.96));

	// Subsurface crest scattering
	float crest_height = clamp((wave_crest + 0.3) / max(wave_amplitude_mult, 0.5), 0.0, 1.0);
	vec3 water_color = mix(absorbed_water, scatter_color.rgb, crest_height * 0.35 * (1.0 - n_dot_v));

	// Foam calculation: Wave crest agitation + shoreline/hull contact foam
	float crest_foam = smoothstep(foam_threshold * wave_amplitude_mult, (foam_threshold + 0.28) * wave_amplitude_mult, wave_crest);
	float contact_foam = clamp(1.0 - smoothstep(0.02, 0.28, water_depth), 0.0, 1.0);

	// Procedural foam bubble texture modulation
	float bubble_noise = sin(p.x * 12.0 + t * 2.0) * cos(p.y * 12.0 - t * 1.8);
	float foam_pattern = clamp((bubble_noise + 0.5) * 0.5, 0.0, 1.0);
	float foam_mask = clamp(crest_foam * (0.7 + 0.3 * foam_pattern) + contact_foam * 0.85, 0.0, 1.0);

	// Blend water surface with foam and sky reflection
	vec3 final_color = mix(water_color, foam_color.rgb, foam_mask);
	vec3 sky_reflection = vec3(0.75, 0.88, 1.0);
	final_color = mix(final_color, sky_reflection, fresnel * 0.45 * (1.0 - foam_mask));

	ALBEDO = final_color;
	METALLIC = mix(metallic, 0.0, foam_mask);
	ROUGHNESS = mix(roughness, 0.75, foam_mask);
	SPECULAR = mix(0.9, 0.2, foam_mask);
	ALPHA = mix(clamp(0.85 + depth_factor * 0.15, 0.85, 1.0), 1.0, foam_mask);
}
