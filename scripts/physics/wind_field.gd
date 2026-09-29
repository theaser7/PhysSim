class_name WindField
extends Node

## 3D Turbulent Wind Field with divergence-free curl noise and aerodynamic lift/drag model

@export var noise_frequency: float = 0.08
@export var gust_frequency: float = 0.2
@export var air_density: float = 1.225 # kg/m^3

var noise_x: FastNoiseLite
var noise_y: FastNoiseLite
var noise_z: FastNoiseLite

var _sim_time: float = 0.0

func _init() -> void:
	noise_x = FastNoiseLite.new()
	noise_x.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_x.frequency = noise_frequency
	noise_x.seed = 1337

	noise_y = FastNoiseLite.new()
	noise_y.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_y.frequency = noise_frequency
	noise_y.seed = 4242

	noise_z = FastNoiseLite.new()
	noise_z.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_z.frequency = noise_frequency
	noise_z.seed = 8888

func _process(delta: float) -> void:
	if not SimState.is_paused:
		_sim_time += delta * SimState.time_scale

## Returns wind velocity at a specific 3D world position
func get_wind_velocity(pos: Vector3) -> Vector3:
	var base_wind = SimState.get_base_wind_vector()
	var speed = base_wind.length()
	if speed < 0.01:
		return Vector3.ZERO

	var turb_scale = SimState.wind_turbulence * speed * 0.5
	
	# Sample potential field with advection
	var t = _sim_time * 0.8
	var p = (pos * 0.15) - (base_wind.normalized() * t)
	
	# Finite differences to calculate curl: curl(A) = (dAz/dy - dAy/dz, dAx/dz - dAz/dx, dAy/dx - dAx/dy)
	var eps = 0.1
	var inv_2eps = 1.0 / (2.0 * eps)
	
	var dAz_dy = (noise_z.get_noise_3d(p.x, p.y + eps, p.z) - noise_z.get_noise_3d(p.x, p.y - eps, p.z)) * inv_2eps
	var dAy_dz = (noise_y.get_noise_3d(p.x, p.y, p.z + eps) - noise_y.get_noise_3d(p.x, p.y, p.z - eps)) * inv_2eps
	
	var dAx_dz = (noise_x.get_noise_3d(p.x, p.y, p.z + eps) - noise_x.get_noise_3d(p.x, p.y, p.z - eps)) * inv_2eps
	var dAz_dx = (noise_z.get_noise_3d(p.x + eps, p.y, p.z) - noise_z.get_noise_3d(p.x - eps, p.y, p.z)) * inv_2eps
	
	var dAy_dx = (noise_y.get_noise_3d(p.x + eps, p.y, p.z) - noise_y.get_noise_3d(p.x - eps, p.y, p.z)) * inv_2eps
	var dAx_dy = (noise_x.get_noise_3d(p.x, p.y + eps, p.z) - noise_x.get_noise_3d(p.x, p.y - eps, p.z)) * inv_2eps
	
	var curl = Vector3(
		dAz_dy - dAy_dz,
		dAx_dz - dAz_dx,
		dAy_dx - dAx_dy
	)
	
	# Periodic gusting
	var gust = 1.0 + 0.3 * sin(_sim_time * gust_frequency * TAU)
	
	return (base_wind * gust) + (curl * turb_scale)

## Computes aerodynamic force (lift + drag) acting on a surface triangle
func compute_aerodynamic_force(
	p0: Vector3, p1: Vector3, p2: Vector3,
	v_surf: Vector3
) -> Dictionary:
	var normal = (p1 - p0).cross(p2 - p0)
	var area_twice = normal.length()
	if area_twice < 0.00001:
		return {"force": Vector3.ZERO, "normal": Vector3.UP, "center": p0, "rel_vel": Vector3.ZERO}

	var area = area_twice * 0.5
	var unit_normal = normal / area_twice
	var center = (p0 + p1 + p2) / 3.0

	var v_wind = get_wind_velocity(center)
	var v_rel = v_wind - v_surf
	var speed_rel = v_rel.length()
	if speed_rel < 0.001:
		return {"force": Vector3.ZERO, "normal": unit_normal, "center": center, "rel_vel": v_rel}

	var dynamic_pressure = 0.5 * air_density * speed_rel * speed_rel
	var cos_theta = v_rel.dot(unit_normal) / speed_rel
	
	# Normal pressure force
	var f_normal = unit_normal * (dynamic_pressure * area * 2.0 * cos_theta * abs(cos_theta))
	
	# Skin drag along surface flow
	var v_tangent = v_rel - (unit_normal * (v_rel.dot(unit_normal)))
	var f_tangent = Vector3.ZERO
	if v_tangent.length_squared() > 0.0001:
		f_tangent = v_tangent.normalized() * (dynamic_pressure * area * 0.05)

	var total_force = f_normal + f_tangent
	return {
		"force": total_force,
		"normal": unit_normal,
		"center": center,
		"rel_vel": v_rel,
		"wind_vel": v_wind
	}
