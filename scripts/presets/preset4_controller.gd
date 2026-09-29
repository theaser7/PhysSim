class_name Preset4Controller
extends Node3D

## Controller for Preset 4: Custom Sandbox with interactive model loading and role assignment

@onready var spawn_point: Node3D = $SpawnPoint
@onready var ocean: OceanSystem = get_node_or_null("OceanSystem") as OceanSystem
@onready var wind: WindField = $WindField
@onready var streamlines: StreamlineVisualizer = $StreamlineVisualizer
@onready var spawned_container: Node3D = $SpawnedModels

func _ready() -> void:
	streamlines.wind_field = wind
	SimState.custom_model_loaded.connect(_on_custom_model_loaded)

func reset_preset() -> void:
	for child in spawned_container.get_children():
		child.queue_free()

func _on_custom_model_loaded(mesh: Mesh, model_name: String, role: String) -> void:
	print("[Preset 4] Spawning custom model: ", model_name, " with role: ", role)
	
	match role:
		"RigidBody":
			_spawn_rigid_body(mesh, model_name)
		"FloatingBody":
			_spawn_floating_body(mesh, model_name)
		"ClothBody":
			_spawn_cloth_body(mesh, model_name)
		_:
			_spawn_rigid_body(mesh, model_name)

func _spawn_rigid_body(mesh: Mesh, model_name: String) -> void:
	var rb = RigidBody3D.new()
	rb.name = "RB_" + model_name
	rb.mass = 50.0
	rb.global_position = spawn_point.global_position + Vector3(randf_range(-1, 1), randf_range(0, 2), randf_range(-1, 1))

	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(randf_range(0.3, 0.9), randf_range(0.3, 0.9), randf_range(0.3, 0.9))
	mat.roughness = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	rb.add_child(mi)

	var cs = CollisionShape3D.new()
	var aabb = mesh.get_aabb()
	var box = BoxShape3D.new()
	box.size = Vector3(max(0.5, aabb.size.x), max(0.5, aabb.size.y), max(0.5, aabb.size.z))
	cs.shape = box
	cs.position = aabb.get_center()
	rb.add_child(cs)

	spawned_container.add_child(rb)

	var root = get_tree().current_scene
	if root and root.has_node("VectorVisualizer"):
		var vv = root.get_node("VectorVisualizer") as VectorVisualizer
		vv.register_tracked_object(rb)

func _spawn_floating_body(mesh: Mesh, model_name: String) -> void:
	var fb = BuoyancyBody.new()
	fb.name = "Float_" + model_name
	if ocean != null:
		fb.ocean_system = ocean
	fb.mass = 80.0
	fb.global_position = Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2))

	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.7, 0.9)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	fb.add_child(mi)

	var aabb = mesh.get_aabb()
	var cs = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(max(0.5, aabb.size.x), max(0.5, aabb.size.y), max(0.5, aabb.size.z))
	cs.shape = box
	cs.position = aabb.get_center()
	fb.add_child(cs)

	# Generate probes from AABB corners
	var hx = aabb.size.x * 0.4
	var hy = aabb.position.y
	var hz = aabb.size.z * 0.4
	fb.probe_points = [
		Vector3(hx, hy, hz),
		Vector3(-hx, hy, hz),
		Vector3(hx, hy, -hz),
		Vector3(-hx, hy, -hz),
		Vector3(0, hy, 0)
	]
	fb.probe_volume = 1.2

	spawned_container.add_child(fb)

	var root = get_tree().current_scene
	if root and root.has_node("VectorVisualizer"):
		var vv = root.get_node("VectorVisualizer") as VectorVisualizer
		vv.register_tracked_object(fb)

func _spawn_cloth_body(_mesh: Mesh, model_name: String) -> void:
	var cloth = XPBDCloth.new()
	cloth.name = "Cloth_" + model_name
	cloth.cloth_width = 3.0
	cloth.cloth_height = 2.5
	cloth.resolution_x = 12
	cloth.resolution_y = 10
	cloth.wind_field = wind
	cloth.global_position = spawn_point.global_position + Vector3(0, 1.0, 0)

	spawned_container.add_child(cloth)

	var root = get_tree().current_scene
	if root and root.has_node("VectorVisualizer"):
		var vv = root.get_node("VectorVisualizer") as VectorVisualizer
		vv.register_tracked_object(cloth)
