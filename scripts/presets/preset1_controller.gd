class_name Preset1Controller
extends Node3D

## Controller for Preset 1: Ship on ocean waves with aerodynamic wind response

@onready var ocean: OceanSystem = $OceanSystem
@onready var wind: WindField = $WindField
@onready var ship: BuoyancyBody = $Ship
@onready var model_anchor: Node3D = $Ship/ModelAnchor
@onready var streamlines: StreamlineVisualizer = $StreamlineVisualizer

func _ready() -> void:
	# Configure ship and ocean coupling
	ship.ocean_system = ocean

	# Connect streamline visualizer to wind field
	if streamlines:
		streamlines.wind_field = wind

	_setup_ship_model()

	# Hook into vector visualizer
	var root = get_tree().current_scene
	if root and root.has_node("VectorVisualizer"):
		var vv = root.get_node("VectorVisualizer") as VectorVisualizer
		vv.clear_tracked_objects()
		vv.register_tracked_object(ship)

func _setup_ship_model() -> void:
	# Load user-provided model if available
	var stl_path = "res://pirate_ship_LowPoly.stl"
	if FileAccess.file_exists(stl_path):
		var mesh = STLLoader.load_stl_file(stl_path)
		if mesh:
			var mi = MeshInstance3D.new()
			mi.name = "ShipModelInstance"
			mi.mesh = mesh
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.62, 0.44, 0.28, 1.0)
			mat.roughness = 0.55
			mat.metallic = 0.05
			mi.material_override = mat

			# Center model on ship keel and waterline
			mi.transform.origin = Vector3(0.0, 2.0, -3.2)
			mi.scale = Vector3(0.85, 0.85, 0.85)
			model_anchor.add_child(mi)
			return

	# Clean placeholder frame for custom user model
	var placeholder = MeshInstance3D.new()
	placeholder.name = "ModelPlaceholder"
	var box = BoxMesh.new()
	box.size = Vector3(2.4, 1.4, 5.5)
	placeholder.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 0.9, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	placeholder.material_override = mat
	model_anchor.add_child(placeholder)

func reset_preset() -> void:
	ship.global_position = Vector3(0, 0.5, 0)
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	ship.rotation = Vector3.ZERO
