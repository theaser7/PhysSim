shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform bool show_stress = true;
uniform vec4 fabric_color : source_color = vec4(0.92, 0.90, 0.86, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.65;
uniform float specular : hint_range(0.0, 1.0) = 0.2;

// Scientific colormap for stress/strain
vec3 stress_to_color(float s) {
	s = clamp(s, 0.0, 1.0);
	
	// Turbo / Rainbow spectrum: Blue -> Cyan -> Green -> Orange -> Red
	vec3 c0 = vec3(0.05, 0.25, 0.70); // Low tension (Deep Blue)
	vec3 c1 = vec3(0.00, 0.75, 0.85); // Moderate low (Cyan)
	vec3 c2 = vec3(0.15, 0.80, 0.25); // Mid tension (Green)
	vec3 c3 = vec3(0.95, 0.65, 0.05); // High tension (Orange)
	vec3 c4 = vec3(0.90, 0.10, 0.15); // Extreme strain / yield (Red)

	if (s < 0.25) {
		return mix(c0, c1, s / 0.25);
	} else if (s < 0.5) {
		return mix(c1, c2, (s - 0.25) / 0.25);
	} else if (s < 0.75) {
		return mix(c2, c3, (s - 0.5) / 0.25);
	} else {
		return mix(c3, c4, (s - 0.75) / 0.25);
	}
}

void fragment() {
	float stress_val = COLOR.r;
	
	vec3 base_color;
	if (show_stress) {
		base_color = stress_to_color(stress_val);
	} else {
		base_color = fabric_color.rgb;
	}

	// Weave pattern texture effect
	vec2 uv_scaled = UV * 60.0;
	float weave = (sin(uv_scaled.x) * sin(uv_scaled.y)) * 0.05;
	base_color += vec3(weave);

	ALBEDO = base_color;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = 0.0;
}
