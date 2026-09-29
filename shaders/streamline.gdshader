shader_type spatial;
render_mode unshaded, blend_add, depth_draw_opaque, cull_disabled;

uniform float sim_time = 0.0;
uniform float dash_frequency = 12.0;
uniform float dash_speed = 3.0;

varying vec3 vert_color;

void vertex() {
	vert_color = COLOR.rgb;
}

void fragment() {
	// Animated dashes moving along line UV
	float flow = UV.x * dash_frequency - (sim_time * dash_speed);
	float dash = sin(flow);
	float alpha = smoothstep(0.1, 0.5, dash);

	// Emissive glow along the streamline
	vec3 glow_color = vert_color * 1.5;

	ALBEDO = glow_color;
	ALPHA = alpha * 0.85;
}
