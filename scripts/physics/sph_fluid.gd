class_name SPHFluid
extends Node3D

const SPHGrid = preload("res://scripts/physics/sph_grid.gd")

## Real-time 3D SPH (Smoothed Particle Hydrodynamics) fluid simulation with container collisions and pouring emitter

@export var max_particles: int = 600
@export var initial_particle_count: int = 300
@export var particle_radius: float = 0.12
@export var smoothing_radius: float = 0.35
@export var particle_mass: float = 0.025
@export var rest_density: float = 1000.0
@export var gas_stiffness: float = 250.0
@export var restitution: float = 0.3
@export var emitter_active: bool = true
@export var emitter_rate: float = 25.0 # particles/second

# Container boundary box (local space)
@export var bounds_min: Vector3 = Vector3(-1.2, 0.0, -1.2)
@export var bounds_max: Vector3 = Vector3(1.2, 2.5, 1.2)

# Obstacle spheres: Array of Vector4(x, y, z, radius)
var obstacle_spheres: Array[Vector4] = []

# Particle data arrays
var positions: PackedVector3Array = []
var velocities: PackedVector3Array = []
var accelerations: PackedVector3Array = []
var densities: PackedFloat32Array = []
var pressures: PackedFloat32Array = []

var _grid: SPHGrid
var _multimesh_instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _emitter_accumulator: float = 0.0

# Pre-allocated neighbor cache per particle
var _neighbors: Array[PackedInt32Array] = []

# SPH Kernel Constants
var _poly6_factor: float
var _spiky_grad_factor: float
var _visc_lap_factor: float
var _poly6_mass: float
var _spiky_grad_mass: float
var _visc_lap_mass: float
var _h2: float

func _ready() -> void:
	_init_kernel_constants()
	_grid = SPHGrid.new(smoothing_radius, 4096)
	_setup_multimesh()
	_spawn_initial_particles()

func _init_kernel_constants() -> void:
	var h = smoothing_radius
	_h2 = h * h
	var pi = PI
	_poly6_factor = 315.0 / (64.0 * pi * pow(h, 9))
	_spiky_grad_factor = -45.0 / (pi * pow(h, 6))
	_visc_lap_factor = 45.0 / (pi * pow(h, 6))
	_poly6_mass = particle_mass * _poly6_factor
	_spiky_grad_mass = particle_mass * _spiky_grad_factor
	_visc_lap_mass = particle_mass * _visc_lap_factor

func _setup_multimesh() -> void:
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.name = "FluidMultiMesh"
	
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.instance_count = max_particles
	_multimesh.visible_instance_count = 0

	var sphere = SphereMesh.new()
	sphere.radius = particle_radius
	sphere.height = particle_radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	_multimesh.mesh = sphere

	var mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/fluid_sphere.gdshader")
	_multimesh_instance.material_override = mat
	_multimesh_instance.multimesh = _multimesh

	add_child(_multimesh_instance)

func _spawn_initial_particles() -> void:
	positions.clear()
	velocities.clear()
	accelerations.clear()
	densities.clear()
	pressures.clear()

	var count_x = 8
	var count_z = 8
	var spacing = particle_radius * 2.1
	var start_y = 0.3
	var spawned = 0

	var layer = 0
	while spawned < initial_particle_count:
		for x in range(count_x):
			for z in range(count_z):
				if spawned >= initial_particle_count:
					break
				var pos = Vector3(
					(float(x) - float(count_x) * 0.5) * spacing + randf_range(-0.02, 0.02),
					start_y + float(layer) * spacing,
					(float(z) - float(count_z) * 0.5) * spacing + randf_range(-0.02, 0.02)
				)
				_add_particle(pos, Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1)))
				spawned += 1
		layer += 1

func _add_particle(pos: Vector3, vel: Vector3) -> void:
	if positions.size() >= max_particles:
		return
	positions.append(pos)
	velocities.append(vel)
	accelerations.append(Vector3.ZERO)
	densities.append(rest_density)
	pressures.append(0.0)

func _physics_process(delta: float) -> void:
	if SimState.is_paused and not SimState.step_frame_requested:
		return

	var dt = delta * SimState.time_scale
	if dt <= 0.0001:
		return

	# Handle fluid pouring emitter
	if emitter_active and positions.size() < max_particles:
		_emitter_accumulator += dt * emitter_rate
		while _emitter_accumulator >= 1.0 and positions.size() < max_particles:
			_emitter_accumulator -= 1.0
			var spout_pos = Vector3(
				randf_range(-0.2, 0.2),
				bounds_max.y - 0.2,
				randf_range(-0.2, 0.2)
			)
			var spout_vel = Vector3(
				randf_range(-0.3, 0.3),
				-2.5,
				randf_range(-0.3, 0.3)
			)
			_add_particle(spout_pos, spout_vel)

	# Adaptive substepping (1 substep at 60 Hz standard tick, 2 if frame time exceeds threshold)
	var substeps = 1 if dt <= 0.02 else 2
	var sub_dt = dt / float(substeps)
	for s in range(substeps):
		_step_sph(sub_dt)

	_update_multimesh()

func _step_sph(dt: float) -> void:
	var n = positions.size()
	if n == 0:
		return

	if _neighbors.size() < n:
		_neighbors.resize(max(n, 512))

	# 1. Update Spatial Hash Grid
	_grid.clear()
	for i in range(n):
		_grid.insert(i, positions[i])

	# 2. Gather Neighbors & Compute Densities and Tait Pressures
	for i in range(n):
		var pi = positions[i]
		var candidates = _grid.get_candidate_neighbors(pi)
		var rho = 0.0
		var nbr_list = PackedInt32Array()
		var nbr_count = 0

		for j in candidates:
			if i == j:
				continue
			var r_vec = pi - positions[j]
			var r2 = r_vec.length_squared()
			if r2 < _h2:
				nbr_list.append(j)
				nbr_count += 1
				var diff = _h2 - r2
				rho += _poly6_mass * diff * diff * diff
				if nbr_count >= 32:
					break

		_neighbors[i] = nbr_list
		# Self-density contribution
		rho += _poly6_mass * _h2 * _h2 * _h2
		densities[i] = max(rho, rest_density * 0.5)
		pressures[i] = max(0.0, gas_stiffness * (densities[i] - rest_density))

	# 3. Compute Forces using pre-gathered neighbor lists
	var gravity_acc = SimState.gravity
	var visc = SimState.fluid_viscosity
	var visc_mult = visc * _visc_lap_mass
	var h = smoothing_radius

	for i in range(n):
		var pi = positions[i]
		var vi = velocities[i]
		var rho_i = densities[i]
		var p_i = pressures[i]

		var f_press = Vector3.ZERO
		var f_visc = Vector3.ZERO
		var neighbors = _neighbors[i]
		var nbr_size = neighbors.size()

		for k in range(nbr_size):
			var j = neighbors[k]
			var r_vec = pi - positions[j]
			var r2 = r_vec.length_squared()
			if r2 < 0.000001:
				continue
			var dist = sqrt(r2)
			var h_dist = h - dist
			var rho_j = densities[j]
			var p_j = pressures[j]

			# Spiky kernel gradient: direct vector scaling
			var p_scalar = (_spiky_grad_mass * (p_i + p_j) / (2.0 * rho_j) * h_dist * h_dist) / dist
			f_press -= r_vec * p_scalar

			# Viscosity laplacian
			var visc_scalar = visc_mult / rho_j * h_dist
			f_visc += (velocities[j] - vi) * visc_scalar

		var total_force = f_press + f_visc
		accelerations[i] = (total_force / rho_i) + gravity_acc

	# 4. Integrate & Handle Collisions
	var total_ke = 0.0
	var r = particle_radius

	for i in range(n):
		velocities[i] += accelerations[i] * dt
		positions[i] += velocities[i] * dt

		# Container collisions
		_resolve_boundary_collision(i, r)

		# Obstacle collisions
		_resolve_obstacle_collisions(i, r)

		total_ke += 0.5 * particle_mass * velocities[i].length_squared()

	SimState.active_particle_count = n
	SimState.total_kinetic_energy = total_ke

func _resolve_boundary_collision(i: int, r: float) -> void:
	var pos = positions[i]
	var vel = velocities[i]

	# Floor
	if pos.y - r < bounds_min.y:
		pos.y = bounds_min.y + r
		vel.y = -vel.y * restitution
		vel.x *= 0.95
		vel.z *= 0.95

	# Ceiling
	if pos.y + r > bounds_max.y:
		pos.y = bounds_max.y - r
		vel.y = -vel.y * restitution

	# Left (X min)
	if pos.x - r < bounds_min.x:
		pos.x = bounds_min.x + r
		vel.x = -vel.x * restitution
		vel.y *= 0.95
		vel.z *= 0.95

	# Right (X max)
	if pos.x + r > bounds_max.x:
		pos.x = bounds_max.x - r
		vel.x = -vel.x * restitution
		vel.y *= 0.95
		vel.z *= 0.95

	# Front (Z min)
	if pos.z - r < bounds_min.z:
		pos.z = bounds_min.z + r
		vel.z = -vel.z * restitution
		vel.x *= 0.95
		vel.y *= 0.95

	# Back (Z max)
	if pos.z + r > bounds_max.z:
		pos.z = bounds_max.z - r
		vel.z = -vel.z * restitution
		vel.x *= 0.95
		vel.y *= 0.95

	positions[i] = pos
	velocities[i] = vel

func _resolve_obstacle_collisions(i: int, r: float) -> void:
	var pos = positions[i]
	var vel = velocities[i]

	for obs in obstacle_spheres:
		var center = Vector3(obs.x, obs.y, obs.z)
		var obs_r = obs.w
		var delta_pos = pos - center
		var dist = delta_pos.length()
		var min_dist = obs_r + r

		if dist < min_dist and dist > 0.0001:
			var normal = delta_pos / dist
			# Push out
			pos = center + normal * min_dist
			# Reflect velocity along normal with restitution
			var normal_vel = vel.dot(normal)
			if normal_vel < 0.0:
				vel -= normal * ((1.0 + restitution) * normal_vel)
				vel *= 0.92

	positions[i] = pos
	velocities[i] = vel

func _update_multimesh() -> void:
	var count = positions.size()
	_multimesh.visible_instance_count = count

	var t = Transform3D.IDENTITY
	for i in range(count):
		t.origin = positions[i]
		_multimesh.set_instance_transform(i, t)
		var vel = velocities[i]
		_multimesh.set_instance_color(i, Color(vel.x, vel.y, vel.z, 1.0))
