class_name Preset3Controller
extends Node3D

## Controller for Preset 3: Aerodynamic wind tunnel with cloth banner and streamlines

@onready var wind: WindField = $WindField
@onready var banner: XPBDCloth = $BannerCloth
@onready var streamlines: StreamlineVisualizer = $StreamlineVisualizer

func _ready() -> void:
	banner.wind_field = wind
	streamlines.wind_field = wind

	# Hook into vector visualizer
	var root = get_tree().current_scene
	if root and root.has_node("VectorVisualizer"):
		var vv = root.get_node("VectorVisualizer") as VectorVisualizer
		vv.clear_tracked_objects()
		vv.register_tracked_object(banner)

func reset_preset() -> void:
	banner._init_cloth_grid()
