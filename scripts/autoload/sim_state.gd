extends Node

## Global simulation singleton managing physics parameters, telemetry, and signals

signal preset_change_requested(index: int)
signal params_changed()
signal step_executed()
signal reset_current_preset()
signal custom_model_loaded(mesh: Mesh, model_name: String, role: String)

# Physical parameters
var gravity: Vector3 = Vector3(0, -9.81, 0)
var time_scale: float = 1.0
var is_paused: bool = false
var step_frame_requested: bool = false

# Wind parameters
var wind_speed: float = 8.0 # m/s
var wind_direction_deg: float = 45.0 # degrees from north (Z+)
var wind_turbulence: float = 0.35 # turbulence intensity multiplier

# SPH Fluid parameters
var fluid_viscosity: float = 0.15
var fluid_rest_density: float = 1000.0
var fluid_gas_constant: float = 200.0
var fluid_particle_radius: float = 0.12

# Ocean parameters
var ocean_wave_amplitude: float = 0.8
var ocean_wave_speed: float = 1.0

# Visualization toggles
var show_velocity_vectors: bool = true
var show_acceleration_vectors: bool = false
var show_streamlines: bool = true
var show_cloth_stress: bool = true

# Telemetry metrics
var fps: float = 60.0
var frame_time_ms: float = 16.6
var active_particle_count: int = 0
var total_kinetic_energy: float = 0.0
var active_preset_index: int = 0
var camera_mode: String = "Orbit"

# Helper vector for wind direction
func get_base_wind_vector() -> Vector3:
	var rad = deg_to_rad(wind_direction_deg)
	return Vector3(sin(rad), 0.0, cos(rad)).normalized() * wind_speed

func toggle_pause() -> void:
	is_paused = !is_paused
	params_changed.emit()

func request_step() -> void:
	step_frame_requested = true
	is_paused = true
	step_executed.emit()

func request_reset() -> void:
	reset_current_preset.emit()

func set_preset(idx: int) -> void:
	active_preset_index = idx
	preset_change_requested.emit(idx)

func _process(delta: float) -> void:
	fps = Engine.get_frames_per_second()
	frame_time_ms = delta * 1000.0
