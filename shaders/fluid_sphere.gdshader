shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Blender-style photorealistic liquid/fluid shader
// Refractive, translucent liquid with specular glints and velocity aeration

uniform vec4 water_deep : source_color = vec4(0.03, 0.30, 0.62, 0.92);
uniform vec4 water_shallow : source_color = vec4(0.10, 0.60, 0.88, 0.85);
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.03;
uniform float metallic : hint_range(0.0, 1.0) = 0.02;
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.04;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

varying vec3 instance_vel;
varying vec3 world_normal;

void vertex() {
	instance_vel = COLOR.rgb;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float speed = length(instance_vel);
	float aeration = clamp((speed - 2.8) / 4.5, 0.0, 1.0);

	// Fresnel factor (water IOR 1.33)
	float n_dot_v = max(dot(NORMAL, VIEW), 0.0);
	float fresnel = 0.04 + (1.0 - 0.04) * pow(1.0 - n_dot_v, 4.0);

	// Soft silhouette edge falloff to eliminate discrete sphere ball seams
	// Spherical optical thickness is maximum at center and drops smoothly to 0 at perimeter
	float edge_softness = smoothstep(0.02, 0.40, n_dot_v);
	float optical_thickness = pow(n_dot_v, 0.55);

	// Screen-space refraction through liquid droplets (corrected view-space UV offset)
	vec2 refr_offset = vec2(NORMAL.x, -NORMAL.y) * refraction_strength * edge_softness;
	vec3 bg_color = textureLod(screen_texture, SCREEN_UV + refr_offset, 0.0).rgb;

	// Cohesive liquid body absorption & transmission
	vec3 liquid_body = mix(water_shallow.rgb, water_deep.rgb, optical_thickness * 0.85);
	vec3 transmitted = mix(bg_color * liquid_body * 1.25, liquid_body, clamp(optical_thickness * 0.75, 0.3, 0.85));

	// Aeration and splash froth
	vec3 fluid_color = mix(transmitted, foam_color.rgb, aeration * 0.65);

	// Specular rim / sky reflection
	vec3 specular_reflection = vec3(0.85, 0.94, 1.0);
	fluid_color = mix(fluid_color, specular_reflection, fresnel * 0.65 * (1.0 - aeration * 0.5));

	ALBEDO = fluid_color;
	ROUGHNESS = mix(roughness, 0.45, aeration);
	METALLIC = metallic;
	SPECULAR = mix(0.98, 0.3, aeration);
	// Soft alpha fading at edges makes overlapping particles merge into unified water volume
	ALPHA = clamp(optical_thickness * water_deep.a * edge_softness + aeration * 0.4, 0.0, 0.96);
}
