shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.08, 0.55, 0.85, 0.9);
uniform vec4 foam_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.08;
uniform float metallic : hint_range(0.0, 1.0) = 0.05;

varying vec3 instance_vel;

void vertex() {
	// Instance custom data can carry particle velocity or state
	instance_vel = COLOR.rgb;
}

void fragment() {
	float speed = length(instance_vel);
	float foam_factor = clamp((speed - 3.0) / 5.0, 0.0, 1.0);

	// Fresnel reflection
	float fresnel = pow(1.0 - dot(NORMAL, VIEW), 3.0);
	vec3 base = mix(water_color.rgb, foam_color.rgb, foam_factor);
	vec3 col = mix(base, vec3(0.9, 0.95, 1.0), fresnel * 0.5);

	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.8;
}
