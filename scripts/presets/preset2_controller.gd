class_name Preset2Controller
extends Node3D

## Controller for Preset 2: 3D SPH fluid pouring into containers and splashing

@onready var fluid: SPHFluid = $SPHFluid

func _ready() -> void:
	var root = get_tree().current_scene
	if root and root.has_node("VectorVisualizer"):
		var vv = root.get_node("VectorVisualizer") as VectorVisualizer
		vv.clear_tracked_objects()

func reset_preset() -> void:
	fluid._spawn_initial_particles()
