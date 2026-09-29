class_name MainController
extends Node3D

## Main application controller managing preset swapping, camera framing, and global environment

@onready var preset_container: Node3D = $PresetContainer
@onready var camera: FreeCamera = $FreeCamera
@onready var hud: HUDController = $HUD
@onready var vector_visualizer: VectorVisualizer = $VectorVisualizer

var preset_scenes: Array[PackedScene] = [
	preload("res://scenes/presets/preset1_ship_ocean.tscn"),
	preload("res://scenes/presets/preset2_sph_fluid.tscn"),
	preload("res://scenes/presets/preset3_wind_tunnel.tscn"),
	preload("res://scenes/presets/preset4_sandbox.tscn")
]

var active_preset_instance: Node3D = null

func _ready() -> void:
	hud.camera = camera
	SimState.preset_change_requested.connect(_load_preset)
	SimState.reset_current_preset.connect(_reset_active_preset)
	
	# Load default Preset 1 (Ship & Ocean)
	_load_preset(0)

func _load_preset(index: int) -> void:
	if index < 0 or index >= preset_scenes.size():
		return

	if active_preset_instance:
		active_preset_instance.queue_free()
		active_preset_instance = null

	var scene = preset_scenes[index]
	active_preset_instance = scene.instantiate()
	preset_container.add_child(active_preset_instance)

	# Adjust camera position and view framing per preset
	match index:
		0: # Ship on Ocean
			camera.reset_view(Vector3(0.0, 1.5, 0.0), 18.0)
		1: # SPH Fluid Basin
			camera.reset_view(Vector3(0.0, 1.3, 0.0), 6.5)
		2: # Wind Tunnel
			camera.reset_view(Vector3(0.0, 1.8, 0.0), 11.0)
		3: # Custom Sandbox
			camera.reset_view(Vector3(0.0, 2.0, 0.0), 16.0)

func _reset_active_preset() -> void:
	if active_preset_instance and active_preset_instance.has_method("reset_preset"):
		active_preset_instance.call("reset_preset")
	else:
		_load_preset(SimState.active_preset_index)
