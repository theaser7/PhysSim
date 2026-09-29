class_name VectorVisualizer
extends Node3D

## 3D vector arrow renderer for velocities, accelerations, and forces with scientific colormap

@export var max_arrows: int = 150
@export var velocity_scale: float = 0.4
@export var accel_scale: float = 0.2

var _immediate_mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _line_material: StandardMaterial3D

# Tracked entities: Array of Dictionaries { "node": Node3D, "type": "body" | "cloth" }
var tracked_objects: Array[Node3D] = []

func _ready() -> void:
	_setup_mesh()

func _setup_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "VectorMeshInstance"
	_mesh_instance.top_level = true

	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _immediate_mesh

	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance.material_override = _line_material

	add_child(_mesh_instance)

func register_tracked_object(obj: Node3D) -> void:
	if not tracked_objects.has(obj):
		tracked_objects.append(obj)

func clear_tracked_objects() -> void:
	tracked_objects.clear()

func _process(_delta: float) -> void:
	if not SimState.show_velocity_vectors and not SimState.show_acceleration_vectors:
		_mesh_instance.visible = false
		return

	_mesh_instance.visible = true
	_render_vectors()

func _render_vectors() -> void:
	_immediate_mesh.clear_surfaces()

	var arrows: Array[Dictionary] = []

	for obj in tracked_objects:
		if not is_instance_valid(obj):
			continue

		if obj is RigidBody3D:
			var rb = obj as RigidBody3D
			var pos = rb.global_transform.origin
			
			# Velocity vector
			if SimState.show_velocity_vectors:
				var vel = rb.linear_velocity
				if vel.length_squared() > 0.01:
					arrows.append({"origin": pos, "vec": vel * velocity_scale, "col": _mag_to_color(vel.length(), 15.0)})

			# Forward / Thrust direction
			if SimState.show_acceleration_vectors:
				var fwd = -rb.global_transform.basis.z * 2.0
				arrows.append({"origin": pos + Vector3(0, 0.5, 0), "vec": fwd, "col": Color(1.0, 0.8, 0.1)})

		elif obj is XPBDCloth:
			var cloth = obj as XPBDCloth
			var step = max(1, cloth.positions.size() / 25)

			for i in range(0, cloth.positions.size(), step):
				var p = cloth.positions[i]
				var v = cloth.velocities[i]
				if SimState.show_velocity_vectors and v.length_squared() > 0.05:
					arrows.append({"origin": p, "vec": v * velocity_scale, "col": _mag_to_color(v.length(), 8.0)})

	if arrows.is_empty():
		return

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
	for a in arrows:
		_draw_arrow(a["origin"], a["vec"], a["col"])
	_immediate_mesh.surface_end()

func _draw_arrow(origin: Vector3, vec: Vector3, col: Color) -> void:
	var target = origin + vec
	var dir = vec.normalized()
	var len = vec.length()
	if len < 0.05:
		return

	# Main shaft line
	_immediate_mesh.surface_set_color(col)
	_immediate_mesh.surface_add_vertex(origin)
	_immediate_mesh.surface_set_color(col)
	_immediate_mesh.surface_add_vertex(target)

	# Arrow head side prongs
	var side = dir.cross(Vector3.UP if abs(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var head_len = min(0.35, len * 0.25)
	var head_base = target - dir * head_len
	var h1 = head_base + side * (head_len * 0.5)
	var h2 = head_base - side * (head_len * 0.5)

	_immediate_mesh.surface_set_color(col)
	_immediate_mesh.surface_add_vertex(target)
	_immediate_mesh.surface_set_color(col)
	_immediate_mesh.surface_add_vertex(h1)

	_immediate_mesh.surface_set_color(col)
	_immediate_mesh.surface_add_vertex(target)
	_immediate_mesh.surface_set_color(col)
	_immediate_mesh.surface_add_vertex(h2)

func _mag_to_color(mag: float, max_mag: float) -> Color:
	var t = clamp(mag / max(0.1, max_mag), 0.0, 1.0)
	if t < 0.33:
		return Color(0.1, 0.4, 1.0).lerp(Color(0.0, 1.0, 0.8), t / 0.33)
	elif t < 0.66:
		return Color(0.0, 1.0, 0.8).lerp(Color(1.0, 0.9, 0.1), (t - 0.33) / 0.33)
	else:
		return Color(1.0, 0.9, 0.1).lerp(Color(1.0, 0.1, 0.2), (t - 0.66) / 0.34)
