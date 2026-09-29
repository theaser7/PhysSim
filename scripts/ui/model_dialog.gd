class_name ModelDialog
extends PanelContainer

const STLLoader = preload("res://scripts/loaders/stl_loader.gd")
const BlendLoader = preload("res://scripts/loaders/blend_loader.gd")

## Model import and submesh role assignment UI controller

@onready var btn_load_stl: Button = $VBox/HBoxLoaders/BtnLoadSTL
@onready var btn_load_blend: Button = $VBox/HBoxLoaders/BtnLoadBlend
@onready var btn_spawn_sample_hull: Button = $VBox/HBoxSamples/BtnSampleHull
@onready var btn_spawn_sample_wing: Button = $VBox/HBoxSamples/BtnSampleWing
@onready var opt_role: OptionButton = $VBox/HBoxRole/OptRole
@onready var lbl_status: Label = $VBox/LblLoadStatus

var _file_dialog: FileDialog

func _ready() -> void:
	_setup_role_options()
	_setup_file_dialog()
	_connect_events()

func _setup_role_options() -> void:
	opt_role.clear()
	opt_role.add_item("RigidBody (Solid Obstacle)", 0)
	opt_role.add_item("FloatingBody (Buoyant Hull)", 1)
	opt_role.add_item("ClothBody (XPBD Dynamic Cloth)", 2)
	opt_role.select(0)

func _setup_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	add_child(_file_dialog)

func _connect_events() -> void:
	btn_load_stl.pressed.connect(_on_load_stl_pressed)
	btn_load_blend.pressed.connect(_on_load_blend_pressed)
	btn_spawn_sample_hull.pressed.connect(_spawn_procedural_hull)
	btn_spawn_sample_wing.pressed.connect(_spawn_procedural_wing)

func _on_load_stl_pressed() -> void:
	_file_dialog.filters = PackedStringArray(["*.stl ; STL 3D Models"])
	_file_dialog.file_selected.disconnect(_handle_blend_file) if _file_dialog.file_selected.is_connected(_handle_blend_file) else null
	if not _file_dialog.file_selected.is_connected(_handle_stl_file):
		_file_dialog.file_selected.connect(_handle_stl_file)
	_file_dialog.popup_centered(Vector2i(800, 600))

func _on_load_blend_pressed() -> void:
	_file_dialog.filters = PackedStringArray(["*.blend ; Blender Project Files"])
	_file_dialog.file_selected.disconnect(_handle_stl_file) if _file_dialog.file_selected.is_connected(_handle_stl_file) else null
	if not _file_dialog.file_selected.is_connected(_handle_blend_file):
		_file_dialog.file_selected.connect(_handle_blend_file)
	_file_dialog.popup_centered(Vector2i(800, 600))

func _handle_stl_file(path: String) -> void:
	lbl_status.text = "Loading STL: " + path.get_file() + "..."
	var mesh = STLLoader.load_stl_file(path)
	if mesh:
		var role = _get_selected_role()
		lbl_status.text = "Loaded STL successfully! Assigned: " + role
		SimState.custom_model_loaded.emit(mesh, path.get_file(), role)
	else:
		lbl_status.text = "Error parsing STL file."

func _handle_blend_file(path: String) -> void:
	lbl_status.text = "Invoking Blender 5.2 headless export for " + path.get_file() + "..."
	var root_node = BlendLoader.load_blend_file(path)
	if root_node:
		var role = _get_selected_role()
		# Find first MeshInstance3D
		var mesh_inst = _find_first_mesh_instance(root_node)
		if mesh_inst and mesh_inst.mesh:
			lbl_status.text = "Loaded Blend successfully! Assigned: " + role
			SimState.custom_model_loaded.emit(mesh_inst.mesh, path.get_file(), role)
		else:
			lbl_status.text = "Imported blend scene has no mesh objects."
	else:
		lbl_status.text = "Failed to export/import .blend file."

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found = _find_first_mesh_instance(child)
		if found:
			return found
	return null

func _get_selected_role() -> String:
	match opt_role.selected:
		0: return "RigidBody"
		1: return "FloatingBody"
		2: return "ClothBody"
		_: return "RigidBody"

func _spawn_procedural_hull() -> void:
	var mesh = _generate_hull_mesh()
	SimState.custom_model_loaded.emit(mesh, "Sample_Hull", _get_selected_role())
	lbl_status.text = "Spawned Procedural Ship Hull (" + _get_selected_role() + ")"

func _spawn_procedural_wing() -> void:
	var mesh = _generate_airfoil_mesh()
	SimState.custom_model_loaded.emit(mesh, "Sample_Airfoil", _get_selected_role())
	lbl_status.text = "Spawned Procedural Aerofoil (" + _get_selected_role() + ")"

func _generate_hull_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Procedural pointed boat hull
	var length = 4.0
	var width = 1.6
	var height = 1.0

	var bow = Vector3(0.0, 0.4, length * 0.5)
	var stern_top_l = Vector3(width * 0.5, height * 0.5, -length * 0.5)
	var stern_top_r = Vector3(-width * 0.5, height * 0.5, -length * 0.5)
	var stern_bot = Vector3(0.0, -height * 0.5, -length * 0.5)
	var keel_mid = Vector3(0.0, -height * 0.5, 0.0)
	var bow_keel = Vector3(0.0, -height * 0.2, length * 0.4)
	var mid_l = Vector3(width * 0.5, height * 0.5, 0.0)
	var mid_r = Vector3(-width * 0.5, height * 0.5, 0.0)

	# Port triangles
	st.add_vertex(bow); st.add_vertex(mid_l); st.add_vertex(bow_keel)
	st.add_vertex(bow_keel); st.add_vertex(mid_l); st.add_vertex(keel_mid)
	st.add_vertex(mid_l); st.add_vertex(stern_top_l); st.add_vertex(keel_mid)
	st.add_vertex(stern_top_l); st.add_vertex(stern_bot); st.add_vertex(keel_mid)

	# Starboard triangles
	st.add_vertex(bow); st.add_vertex(bow_keel); st.add_vertex(mid_r)
	st.add_vertex(bow_keel); st.add_vertex(keel_mid); st.add_vertex(mid_r)
	st.add_vertex(mid_r); st.add_vertex(keel_mid); st.add_vertex(stern_top_r)
	st.add_vertex(stern_top_r); st.add_vertex(keel_mid); st.add_vertex(stern_bot)

	# Stern transom
	st.add_vertex(stern_top_l); st.add_vertex(stern_top_r); st.add_vertex(stern_bot)

	# Deck
	st.add_vertex(bow); st.add_vertex(mid_r); st.add_vertex(mid_l)
	st.add_vertex(mid_l); st.add_vertex(mid_r); st.add_vertex(stern_top_r)
	st.add_vertex(mid_l); st.add_vertex(stern_top_r); st.add_vertex(stern_top_l)

	st.generate_normals()
	return st.commit()

func _generate_airfoil_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# NACA-like cambered wing
	var span = 4.0
	var chord = 1.8
	var thick = 0.3
	
	var le = Vector3(0.0, 0.0, chord * 0.5)
	var te = Vector3(0.0, 0.0, -chord * 0.5)
	var top = Vector3(0.0, thick, chord * 0.1)
	var bot = Vector3(0.0, -thick * 0.2, chord * 0.1)

	var le_left = le + Vector3(span * 0.5, 0, 0)
	var le_right = le - Vector3(span * 0.5, 0, 0)
	var te_left = te + Vector3(span * 0.5, 0, 0)
	var te_right = te - Vector3(span * 0.5, 0, 0)
	var top_left = top + Vector3(span * 0.5, 0, 0)
	var top_right = top - Vector3(span * 0.5, 0, 0)
	var bot_left = bot + Vector3(span * 0.5, 0, 0)
	var bot_right = bot - Vector3(span * 0.5, 0, 0)

	# Upper surface
	st.add_vertex(le_left); st.add_vertex(top_left); st.add_vertex(le_right)
	st.add_vertex(le_right); st.add_vertex(top_left); st.add_vertex(top_right)
	st.add_vertex(top_left); st.add_vertex(te_left); st.add_vertex(top_right)
	st.add_vertex(top_right); st.add_vertex(te_left); st.add_vertex(te_right)

	# Lower surface
	st.add_vertex(le_left); st.add_vertex(le_right); st.add_vertex(bot_left)
	st.add_vertex(le_right); st.add_vertex(bot_right); st.add_vertex(bot_left)
	st.add_vertex(bot_left); st.add_vertex(bot_right); st.add_vertex(te_left)
	st.add_vertex(bot_right); st.add_vertex(te_right); st.add_vertex(te_left)

	st.generate_normals()
	return st.commit()
