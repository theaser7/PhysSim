class_name Preset1Controller
extends Node3D

## Controller for Preset 1: Ship on ocean waves with flapping sail and wind aerodynamics

@onready var ocean: OceanSystem = $OceanSystem
@onready var wind: WindField = $WindField
@onready var ship: BuoyancyBody = $Ship
@onready var sail: XPBDCloth = $Ship/Sail
@onready var streamlines: StreamlineVisualizer = $StreamlineVisualizer

func _ready() -> void:
	# Configure ship and sail coupling
	ship.ocean_system = ocean
	sail.wind_field = wind
	sail.connected_body = ship

	# Connect streamline visualizer to wind field
	streamlines.wind_field = wind

	# Hook into vector visualizer
	var root = get_tree().current_scene
	if root and root.has_node("VectorVisualizer"):
		var vv = root.get_node("VectorVisualizer") as VectorVisualizer
		vv.clear_tracked_objects()
		vv.register_tracked_object(ship)
		vv.register_tracked_object(sail)

func reset_preset() -> void:
	ship.global_position = Vector3(0, 0.5, 0)
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	ship.rotation = Vector3.ZERO
