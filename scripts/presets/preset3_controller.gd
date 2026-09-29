class_name Preset3Controller
extends Node3D

## Controller for Preset 3: Aerodynamic wind tunnel with cloth banner and streamlines

@onready var wind: WindField = $WindField
@onready var banner: XPBDCloth = $BannerCloth
@onready var streamlines: StreamlineVisualizer = $StreamlineVisualizer

func _ready() -> void:
	banner.wind_field = wind
	streamlines.wind_field = wind
	SimState.custom_model_loaded.connect(_on_custom_model_loaded)

	# Hook into vector visualizer
	var root = get_tree().current_scene
	if root and root.has_node("VectorVisualizer"):
		var vv = root.get_node("VectorVisualizer") as VectorVisualizer
		vv.clear_tracked_objects()
		vv.register_tracked_object(banner)

func reset_preset() -> void:
	var existing = get_node_or_null("CustomModelInstance")
	if existing:
		existing.queue_free()
	banner._init_cloth_grid()

func _on_custom_model_loaded(mesh: Mesh, _name: String, _role: String) -> void:
	if mesh == null:
		return
	var existing = get_node_or_null("CustomModelInstance")
	if existing:
		existing.queue_free()
	var mi = MeshInstance3D.new()
	mi.name = "CustomModelInstance"
	mi.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.45, 1.0)
	mat.roughness = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat

	var aabb = mesh.get_aabb()
	var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	var s = 2.0 / max(max_dim, 0.01)
	mi.scale = Vector3(s, s, s)
	mi.position = Vector3(0.0, 1.6, 2.5) - aabb.get_center() * s
	add_child(mi)
