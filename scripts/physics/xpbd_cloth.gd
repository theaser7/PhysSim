class_name XPBDCloth
extends Node3D

## High-performance XPBD dynamic cloth simulation with aerodynamic wind reaction and stress heatmap

@export var cloth_width: float = 4.0
@export var cloth_height: float = 3.0
@export var resolution_x: int = 14
@export var resolution_y: int = 12
@export var total_mass: float = 2.5 # kg
@export var solver_iterations: int = 6
@export var structural_compliance: float = 0.00005
@export var shear_compliance: float = 0.0005
@export var bending_compliance: float = 0.005
@export var damping: float = 0.015

@export var wind_field: WindField
@export var connected_body: RigidBody3D
@export var anchor_top_left: Node3D
@export var anchor_top_right: Node3D
@export var anchor_bottom_left: Node3D
@export var anchor_bottom_right: Node3D

# Internal simulation arrays
var positions: PackedVector3Array = []
var prev_positions: PackedVector3Array = []
var velocities: PackedVector3Array = []
var inv_masses: PackedFloat32Array = []
var vertex_stress: PackedFloat32Array = []
var vertex_colors: PackedColorArray = []

# Constraints: [p1_idx, p2_idx, rest_length, compliance]
var constraints: Array[Vector4] = []

# Triangle indices for rendering and aerodynamic forces
var triangle_indices: PackedInt32Array = []
var uvs: PackedVector2Array = []

var _mesh_instance: MeshInstance3D
var _array_mesh: ArrayMesh
var _cloth_material: ShaderMaterial
var _vertex_count: int = 0
var _triangle_count: int = 0

func _ready() -> void:
	_init_cloth_grid()
	_create_mesh_instance()

func _init_cloth_grid() -> void:
	positions.clear()
	prev_positions.clear()
	velocities.clear()
	inv_masses.clear()
	vertex_stress.clear()
	vertex_colors.clear()
	constraints.clear()
	triangle_indices.clear()
	uvs.clear()

	_vertex_count = resolution_x * resolution_y
	var particle_mass = total_mass / float(_vertex_count)
	var inv_m = 1.0 / particle_mass

	var dx = cloth_width / float(resolution_x - 1)
	var dy = cloth_height / float(resolution_y - 1)

	# Generate particles
	for y in range(resolution_y):
		for x in range(resolution_x):
			var local_pos = Vector3(
				(float(x) - float(resolution_x - 1) * 0.5) * dx,
				(float(resolution_y - 1) * 0.5 - float(y)) * dy,
				0.0
			)
			var world_pos = global_transform * local_pos
			positions.append(world_pos)
			prev_positions.append(world_pos)
			velocities.append(Vector3.ZERO)
			
			# Pin only the side corners/edges (left and right), leaving the middle free to flap in the wind
			var is_pinned = false
			if y == 0:
				if x == 0 or x == resolution_x - 1:
					is_pinned = true

			inv_masses.append(0.0 if is_pinned else inv_m)
			vertex_stress.append(0.0)
			vertex_colors.append(Color(0, 0, 0, 1))
			uvs.append(Vector2(float(x) / float(resolution_x - 1), float(y) / float(resolution_y - 1)))

	# Generate spring constraints: structural, shear, bending
	for y in range(resolution_y):
		for x in range(resolution_x):
			var i = y * resolution_x + x

			# Structural (horizontal)
			if x < resolution_x - 1:
				var j = y * resolution_x + (x + 1)
				_add_constraint(i, j, structural_compliance)

			# Structural (vertical)
			if y < resolution_y - 1:
				var j = (y + 1) * resolution_x + x
				_add_constraint(i, j, structural_compliance)

			# Shear (diagonal 1)
			if x < resolution_x - 1 and y < resolution_y - 1:
				var j = (y + 1) * resolution_x + (x + 1)
				_add_constraint(i, j, shear_compliance)

			# Shear (diagonal 2)
			if x > 0 and y < resolution_y - 1:
				var j = (y + 1) * resolution_x + (x - 1)
				_add_constraint(i, j, shear_compliance)

			# Bending (horizontal skip 1)
			if x < resolution_x - 2:
				var j = y * resolution_x + (x + 2)
				_add_constraint(i, j, bending_compliance)

			# Bending (vertical skip 1)
			if y < resolution_y - 2:
				var j = (y + 2) * resolution_x + x
				_add_constraint(i, j, bending_compliance)

	# Generate triangle indices
	for y in range(resolution_y - 1):
		for x in range(resolution_x - 1):
			var i0 = y * resolution_x + x
			var i1 = y * resolution_x + (x + 1)
			var i2 = (y + 1) * resolution_x + x
			var i3 = (y + 1) * resolution_x + (x + 1)

			triangle_indices.append(i0)
			triangle_indices.append(i1)
			triangle_indices.append(i2)

			triangle_indices.append(i1)
			triangle_indices.append(i3)
			triangle_indices.append(i2)

	_triangle_count = triangle_indices.size() / 3

func _add_constraint(i: int, j: int, compliance: float) -> void:
	var dist = (positions[i] - positions[j]).length()
	constraints.append(Vector4(float(i), float(j), dist, compliance))

func _create_mesh_instance() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "ClothMeshInstance"
	_mesh_instance.top_level = true # Renders directly in world space
	
	_array_mesh = ArrayMesh.new()
	_update_mesh_geometry()
	_mesh_instance.mesh = _array_mesh

	var shader = load("res://shaders/cloth_stress.gdshader")
	if shader:
		_cloth_material = ShaderMaterial.new()
		_cloth_material.shader = shader
		_cloth_material.set_shader_parameter("show_stress", SimState.show_cloth_stress)
		_mesh_instance.material_override = _cloth_material

	add_child(_mesh_instance)

func _physics_process(delta: float) -> void:
	if SimState.is_paused and not SimState.step_frame_requested:
		return

	var dt = delta * SimState.time_scale
	if dt <= 0.0001:
		return

	_step_simulation(dt)
	_update_mesh_geometry()
	
	if _cloth_material:
		_cloth_material.set_shader_parameter("show_stress", SimState.show_cloth_stress)

func _step_simulation(dt: float) -> void:
	var gravity_acc = SimState.gravity

	# 1. Update dynamic anchors if attached to moving objects
	_update_anchor_positions()

	# 2. Predict positions with gravity, aerodynamic forces, and Verlet integration
	var total_aero_force_on_connected_body = Vector3.ZERO
	var total_aero_torque_on_connected_body = Vector3.ZERO
	var body_com = connected_body.global_transform.origin if connected_body else Vector3.ZERO

	# Aerodynamic wind forces applied to cloth triangles
	if wind_field:
		for t in range(_triangle_count):
			var i0 = triangle_indices[t * 3 + 0]
			var i1 = triangle_indices[t * 3 + 1]
			var i2 = triangle_indices[t * 3 + 2]

			var p0 = positions[i0]
			var p1 = positions[i1]
			var p2 = positions[i2]
			var v_surf = (velocities[i0] + velocities[i1] + velocities[i2]) / 3.0

			var aero = wind_field.compute_aerodynamic_force(p0, p1, p2, v_surf)
			var f_tri: Vector3 = aero["force"]

			# Distribute 1/3 of force to each vertex
			var f_vertex = f_tri * (1.0 / 3.0)
			if inv_masses[i0] > 0.0:
				velocities[i0] += f_vertex * (inv_masses[i0] * dt)
			if inv_masses[i1] > 0.0:
				velocities[i1] += f_vertex * (inv_masses[i1] * dt)
			if inv_masses[i2] > 0.0:
				velocities[i2] += f_vertex * (inv_masses[i2] * dt)

			# Transmit thrust to connected body (e.g. ship mast/hull)
			if connected_body:
				total_aero_force_on_connected_body += f_tri
				var r_tri = aero["center"] - body_com
				total_aero_torque_on_connected_body += r_tri.cross(f_tri)

	if connected_body and total_aero_force_on_connected_body.length_squared() > 0.01:
		connected_body.apply_central_force(total_aero_force_on_connected_body)
		connected_body.apply_torque(total_aero_torque_on_connected_body * 0.5)

	# Integrate positions
	for i in range(_vertex_count):
		if inv_masses[i] == 0.0:
			continue # Pinned vertex stays fixed to anchor

		# Gravity & damping
		velocities[i] += gravity_acc * dt
		velocities[i] *= (1.0 - damping)

		prev_positions[i] = positions[i]
		positions[i] += velocities[i] * dt

	# 3. Solve XPBD distance constraints
	var dt2 = dt * dt
	var num_constraints = constraints.size()

	for iter in range(solver_iterations):
		for c_idx in range(num_constraints):
			var c = constraints[c_idx]
			var idx_a = int(c.x)
			var idx_b = int(c.y)
			var rest_len = c.z
			var comp = c.w

			var pa = positions[idx_a]
			var pb = positions[idx_b]
			var delta_p = pa - pb
			var dist = delta_p.length()
			if dist < 0.00001:
				continue

			var c_val = dist - rest_len
			var n = delta_p / dist

			var w_a = inv_masses[idx_a]
			var w_b = inv_masses[idx_b]
			var w_sum = w_a + w_b
			if w_sum <= 0.0:
				continue

			var alpha_tilde = comp / dt2
			var delta_lambda = -c_val / (w_sum + alpha_tilde)

			if w_a > 0.0:
				positions[idx_a] += n * (w_a * delta_lambda)
			if w_b > 0.0:
				positions[idx_b] -= n * (w_b * delta_lambda)

	# 4. Finalize velocities and calculate stress/strain for heatmap
	var strain_sum = PackedFloat32Array()
	strain_sum.resize(_vertex_count)
	strain_sum.fill(0.0)
	var strain_count = PackedInt32Array()
	strain_count.resize(_vertex_count)
	strain_count.fill(0)

	for c_idx in range(num_constraints):
		var c = constraints[c_idx]
		var idx_a = int(c.x)
		var idx_b = int(c.y)
		var rest_len = c.z
		var current_len = (positions[idx_a] - positions[idx_b]).length()
		var strain = max(0.0, (current_len - rest_len) / rest_len)

		strain_sum[idx_a] += strain
		strain_count[idx_a] += 1
		strain_sum[idx_b] += strain
		strain_count[idx_b] += 1

	for i in range(_vertex_count):
		if inv_masses[i] > 0.0:
			velocities[i] = (positions[i] - prev_positions[i]) / dt
		else:
			velocities[i] = Vector3.ZERO

		var count = max(1, strain_count[i])
		var avg_strain = strain_sum[i] / float(count)
		# Map strain to [0, 1] range: 0.15 elongation = max stress 1.0
		var normalized_stress = clamp(avg_strain / 0.12, 0.0, 1.0)
		vertex_stress[i] = normalized_stress
		vertex_colors[i] = Color(normalized_stress, 0.0, 0.0, 1.0)

func _update_anchor_positions() -> void:
	if anchor_top_left:
		_set_anchor_vertex(0, anchor_top_left.global_position)
	if anchor_top_right:
		_set_anchor_vertex(resolution_x - 1, anchor_top_right.global_position)
	if anchor_bottom_left:
		_set_anchor_vertex((resolution_y - 1) * resolution_x, anchor_bottom_left.global_position)
	if anchor_bottom_right:
		_set_anchor_vertex((resolution_y - 1) * resolution_x + (resolution_x - 1), anchor_bottom_right.global_position)

func _set_anchor_vertex(idx: int, target_world_pos: Vector3) -> void:
	if idx >= 0 and idx < _vertex_count:
		inv_masses[idx] = 0.0
		positions[idx] = target_world_pos
		prev_positions[idx] = target_world_pos
		velocities[idx] = Vector3.ZERO

func _update_mesh_geometry() -> void:
	# Compute smooth vertex normals
	var normals = PackedVector3Array()
	normals.resize(_vertex_count)
	normals.fill(Vector3.ZERO)

	for t in range(_triangle_count):
		var i0 = triangle_indices[t * 3 + 0]
		var i1 = triangle_indices[t * 3 + 1]
		var i2 = triangle_indices[t * 3 + 2]

		var n = (positions[i1] - positions[i0]).cross(positions[i2] - positions[i0])
		normals[i0] += n
		normals[i1] += n
		normals[i2] += n

	for i in range(_vertex_count):
		normals[i] = normals[i].normalized()

	# Populate mesh arrays
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = vertex_colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = triangle_indices

	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
