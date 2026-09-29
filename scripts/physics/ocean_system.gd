class_name OceanSystem
extends Node3D

## Gerstner Wave Ocean Simulation for physical buoyancy and visual synchronization

@export var water_density: float = 1025.0 # kg/m^3 (seawater)
@export var plane_size: float = 200.0
@export var mesh_subdivisions: int = 80

var _sim_time: float = 0.0
var _ocean_mesh_instance: MeshInstance3D
var _water_material: ShaderMaterial

# Wave harmonics definitions: [dir_deg, wavelength, amp_ratio, steepness]
const WAVES = [
	Vector4(35.0, 26.0, 0.45, 0.40),
	Vector4(80.0, 15.0, 0.28, 0.35),
	Vector4(10.0, 8.0, 0.18, 0.30),
	Vector4(-45.0, 4.0, 0.09, 0.25)
]

func _ready() -> void:
	_create_ocean_mesh()

func _create_ocean_mesh() -> void:
	_ocean_mesh_instance = MeshInstance3D.new()
	_ocean_mesh_instance.name = "OceanSurface"
	
	var plane = PlaneMesh.new()
	plane.size = Vector2(plane_size, plane_size)
	plane.subdivide_width = mesh_subdivisions
	plane.subdivide_depth = mesh_subdivisions
	_ocean_mesh_instance.mesh = plane

	var shader = load("res://shaders/ocean_water.gdshader")
	if shader:
		_water_material = ShaderMaterial.new()
		_water_material.shader = shader
		_water_material.set_shader_parameter("wave_amplitude_mult", SimState.ocean_wave_amplitude)
		_ocean_mesh_instance.material_override = _water_material

	add_child(_ocean_mesh_instance)

func _process(delta: float) -> void:
	if not SimState.is_paused:
		_sim_time += delta * SimState.time_scale * SimState.ocean_wave_speed
	
	if _water_material:
		_water_material.set_shader_parameter("sim_time", _sim_time)
		_water_material.set_shader_parameter("wave_amplitude_mult", SimState.ocean_wave_amplitude)

## Evaluates ocean surface height at world (x, z)
func get_wave_height(world_pos: Vector3) -> float:
	var total_h = 0.0
	var amp_mult = SimState.ocean_wave_amplitude
	var g = abs(SimState.gravity.y)
	
	for w in WAVES:
		var dir_rad = deg_to_rad(w.x)
		var d = Vector2(sin(dir_rad), cos(dir_rad)).normalized()
		var wavelength = w.y
		var k = TAU / wavelength
		var omega = sqrt(g * k)
		var amp = w.z * amp_mult
		var phi = k * (d.x * world_pos.x + d.y * world_pos.z) - (omega * _sim_time)
		total_h += amp * cos(phi)
		
	return global_position.y + total_h

## Evaluates surface normal at world (x, z)
func get_wave_normal(world_pos: Vector3) -> Vector3:
	var amp_mult = SimState.ocean_wave_amplitude
	var g = abs(SimState.gravity.y)
	var norm_x = 0.0
	var norm_z = 0.0
	var norm_y = 1.0

	for w in WAVES:
		var dir_rad = deg_to_rad(w.x)
		var d = Vector2(sin(dir_rad), cos(dir_rad)).normalized()
		var wavelength = w.y
		var k = TAU / wavelength
		var omega = sqrt(g * k)
		var amp = w.z * amp_mult
		var q = w.w
		var phi = k * (d.x * world_pos.x + d.y * world_pos.z) - (omega * _sim_time)
		
		norm_x -= d.x * (amp * k) * sin(phi)
		norm_z -= d.y * (amp * k) * sin(phi)
		norm_y -= q * (amp * k) * cos(phi)
		
	return Vector3(norm_x, max(norm_y, 0.1), norm_z).normalized()

## Evaluates water orbital velocity at world (x, z)
func get_water_velocity(world_pos: Vector3) -> Vector3:
	var amp_mult = SimState.ocean_wave_amplitude
	var g = abs(SimState.gravity.y)
	var vel = Vector3.ZERO

	for w in WAVES:
		var dir_rad = deg_to_rad(w.x)
		var d = Vector2(sin(dir_rad), cos(dir_rad)).normalized()
		var wavelength = w.y
		var k = TAU / wavelength
		var omega = sqrt(g * k)
		var amp = w.z * amp_mult
		var phi = k * (d.x * world_pos.x + d.y * world_pos.z) - (omega * _sim_time)
		
		vel.x += omega * amp * d.x * cos(phi)
		vel.y += omega * amp * sin(phi)
		vel.z += omega * amp * d.y * cos(phi)

	return vel
