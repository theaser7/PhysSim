class_name StreamlineVisualizer
extends Node3D

## Visualizes 3D wind velocity streamlines with scientific speed colormap and animated dashes

@export var wind_field: WindField
@export var seed_box_min: Vector3 = Vector3(-6.0, 1.0, -6.0)
@export var seed_box_max: Vector3 = Vector3(6.0, 5.0, 6.0)
@export var stream_count_x: int = 5
@export var stream_count_y: int = 4
@export var stream_count_z: int = 5
@export var steps_per_line: int = 22
@export var step_length: float = 0.45

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _material: ShaderMaterial
var _sim_time: float = 0.0

func _ready() -> void:
	_setup_mesh()

func _setup_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "StreamlineMeshInstance"
	_mesh_instance.top_level = true
	
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _immediate_mesh

	var shader = load("res://shaders/streamline.gdshader")
	if shader:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_mesh_instance.material_override = _material

	add_child(_mesh_instance)

func _process(delta: float) -> void:
	if not SimState.show_streamlines:
		_mesh_instance.visible = false
		return

	_mesh_instance.visible = true

	if not SimState.is_paused:
		_sim_time += delta * SimState.time_scale * (SimState.wind_speed / 8.0)

	if _material:
		_material.set_shader_parameter("sim_time", _sim_time)

	_regenerate_streamlines()

func _regenerate_streamlines() -> void:
	if wind_field == null:
		return

	_immediate_mesh.clear_surfaces()
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)

	var dx = (seed_box_max.x - seed_box_min.x) / float(max(1, stream_count_x - 1))
	var dy = (seed_box_max.y - seed_box_min.y) / float(max(1, stream_count_y - 1))
	var dz = (seed_box_max.z - seed_box_min.z) / float(max(1, stream_count_z - 1))

	var max_expected_speed = max(1.0, SimState.wind_speed * 1.5)

	for ix in range(stream_count_x):
		for iy in range(stream_count_y):
			for iz in range(stream_count_z):
				var seed_pos = global_position + Vector3(
					seed_box_min.x + float(ix) * dx,
					seed_box_min.y + float(iy) * dy,
					seed_box_min.z + float(iz) * dz
				)

				# Trace streamline forward using RK2 integration
				var current_pos = seed_pos
				for s in range(steps_per_line - 1):
					var v1 = wind_field.get_wind_velocity(current_pos)
					var speed1 = v1.length()
					if speed1 < 0.01:
						break

					var dir1 = v1.normalized()
					var mid_pos = current_pos + dir1 * (step_length * 0.5)
					
					var v2 = wind_field.get_wind_velocity(mid_pos)
					var dir2 = v2.normalized() if v2.length() > 0.01 else dir1
					var next_pos = current_pos + dir2 * step_length
					var speed2 = v2.length()

					var color1 = _speed_to_color(speed1 / max_expected_speed)
					var color2 = _speed_to_color(speed2 / max_expected_speed)

					var uv1 = Vector2(float(s) / float(steps_per_line), 0.0)
					var uv2 = Vector2(float(s + 1) / float(steps_per_line), 0.0)

					_immediate_mesh.surface_set_color(color1)
					_immediate_mesh.surface_set_uv(uv1)
					_immediate_mesh.surface_add_vertex(current_pos)

					_immediate_mesh.surface_set_color(color2)
					_immediate_mesh.surface_set_uv(uv2)
					_immediate_mesh.surface_add_vertex(next_pos)

					current_pos = next_pos

	_immediate_mesh.surface_end()

func _speed_to_color(t: float) -> Color:
	t = clamp(t, 0.0, 1.0)
	if t < 0.33:
		return Color(0.1, 0.5, 1.0).lerp(Color(0.0, 0.9, 0.8), t / 0.33)
	elif t < 0.66:
		return Color(0.0, 0.9, 0.8).lerp(Color(0.9, 0.85, 0.1), (t - 0.33) / 0.33)
	else:
		return Color(0.9, 0.85, 0.1).lerp(Color(1.0, 0.15, 0.1), (t - 0.66) / 0.34)
