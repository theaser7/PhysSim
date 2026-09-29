class_name BuoyancyBody
extends RigidBody3D

## Archimedes multi-probe hydrodynamic floating body simulation

@export var ocean_system: OceanSystem
@export var total_buoyant_volume: float = 6.0 # m^3
@export var water_drag_coeff: float = 1.2
@export var righting_stiffness: float = 1200.0
@export var roll_pitch_damping: float = 25.0
@export var keel_lateral_drag: float = 6.0

# Local probe coordinates representing ship hull geometry
var probe_points: Array[Vector3] = []
var probe_volume: float = 1.0
var probe_max_submersion: float = 1.2

func _ready() -> void:
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.8, 0.0) # Low in keel for metacentric stability
	if probe_points.is_empty():
		_setup_default_ship_probes()

func _setup_default_ship_probes() -> void:
	# Distributed hull probes: Keel, bilge, and wide waterplane beam to ensure roll stability
	probe_points = [
		# Center Keel
		Vector3(0.0, -0.9, 2.5),
		Vector3(0.0, -0.9, 0.0),
		Vector3(0.0, -0.9, -2.5),

		# Inner bilge (port & starboard, low)
		Vector3(0.7, -0.6, 2.2),
		Vector3(-0.7, -0.6, 2.2),
		Vector3(0.8, -0.6, 0.0),
		Vector3(-0.8, -0.6, 0.0),
		Vector3(0.7, -0.6, -2.2),
		Vector3(-0.7, -0.6, -2.2),

		# Outer beam / waterline (port & starboard - generates powerful righting moments)
		Vector3(1.3, -0.2, 2.0),
		Vector3(-1.3, -0.2, 2.0),
		Vector3(1.4, -0.2, 0.5),
		Vector3(-1.4, -0.2, 0.5),
		Vector3(1.4, -0.2, -0.5),
		Vector3(-1.4, -0.2, -0.5),
		Vector3(1.3, -0.2, -2.0),
		Vector3(-1.3, -0.2, -2.0),

		# Bow and Stern tips
		Vector3(0.0, -0.3, 3.4),
		Vector3(0.0, -0.3, -3.2)
	]
	probe_volume = total_buoyant_volume / float(probe_points.size())

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if SimState.is_paused and not SimState.step_frame_requested:
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return

	if ocean_system == null:
		return

	var rho = ocean_system.water_density
	var g_acc = abs(SimState.gravity.y)
	gravity_scale = g_acc / 9.81
	var submerged_count = 0
	var center_of_mass_world = state.transform.origin

	for p_local in probe_points:
		var p_world = global_transform * p_local
		var wave_h = ocean_system.get_wave_height(p_world)
		var depth = wave_h - p_world.y

		if depth > 0.0:
			submerged_count += 1
			var wave_normal = ocean_system.get_wave_normal(p_world)
			var sub_ratio = clamp(depth / probe_max_submersion, 0.0, 1.5)
			
			# Archimedes buoyant force: F = rho * V * g directed upwards / along wave normal
			var f_buoyant = wave_normal * (rho * probe_volume * g_acc * sub_ratio)

			# Point velocity relative to water orbital flow
			var r = p_world - center_of_mass_world
			var v_point = state.linear_velocity + state.angular_velocity.cross(r)
			var v_water = ocean_system.get_water_velocity(p_world)
			var v_rel = v_point - v_water
			var speed_rel = v_rel.length()

			# Hydrodynamic quadratic drag
			var f_drag = -v_rel * (0.5 * rho * water_drag_coeff * (probe_volume * 0.8) * speed_rel)
			
			# Vertical damping to settle bouncing
			f_drag.y -= v_rel.y * rho * 0.5 * probe_volume

			state.apply_force(f_buoyant + f_drag, r)

	# Keel lateral resistance (ships resist sideways drift, favoring forward surge)
	if submerged_count > 0:
		var lateral_dir = global_transform.basis.x
		var lateral_speed = state.linear_velocity.dot(lateral_dir)
		var keel_force = -lateral_dir * (lateral_speed * keel_lateral_drag * mass)
		state.apply_central_force(keel_force)

	# Metacentric righting torque (prevents capsizing, restores upright posture)
	var current_up = global_transform.basis.y
	var world_up = Vector3.UP
	var alignment = clamp(current_up.dot(world_up), -1.0, 1.0)
	var righting_axis = current_up.cross(world_up)

	if righting_axis.length_squared() > 0.0001:
		var righting_factor = 1.0 - alignment
		var righting_torque = righting_axis.normalized() * (righting_stiffness * righting_factor)
		state.apply_torque(righting_torque)
	elif alignment < 0.0:
		# Upside down: nudge out of inverted equilibrium
		state.apply_torque(global_transform.basis.z * righting_stiffness)

	# Angular hydrodynamic damping in water to suppress roll & pitch oscillations
	if submerged_count > 0:
		var ang_damp = -state.angular_velocity * (roll_pitch_damping * mass * 0.02)
		state.apply_torque(ang_damp)
