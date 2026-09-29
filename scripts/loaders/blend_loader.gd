class_name BlendLoader
extends RefCounted

## Loads .blend files at runtime by invoking headless Blender 5.2 and importing GLTF

const BLENDER_DEFAULT_PATH = "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe"

static func load_blend_file(blend_path: String, custom_blender_path: String = "") -> Node3D:
	var blender_exe = custom_blender_path if not custom_blender_path.is_empty() else BLENDER_DEFAULT_PATH
	
	if not FileAccess.file_exists(blender_exe):
		push_error("[BlendLoader] Blender executable not found at: " + blender_exe)
		return null

	if not FileAccess.file_exists(blend_path):
		push_error("[BlendLoader] Target .blend file not found: " + blend_path)
		return null

	# Temporary output path for GLB file
	var temp_glb = ProjectSettings.globalize_path("user://temp_blend_import.glb")
	var script_user_path = "user://blender_export.py"
	if not FileAccess.file_exists(script_user_path):
		var src_script = FileAccess.get_file_as_string("res://scripts/blender_export.py")
		var out_file = FileAccess.open(script_user_path, FileAccess.WRITE)
		if out_file:
			out_file.store_string(src_script)
			out_file.close()

	var script_path = ProjectSettings.globalize_path(script_user_path)
	var abs_blend_path = ProjectSettings.globalize_path(blend_path)

	print("[BlendLoader] Running headless Blender export...")
	var output = []
	var args = [
		"--background",
		abs_blend_path,
		"--python",
		script_path,
		"--",
		temp_glb
	]

	var exit_code = OS.execute(blender_exe, args, output, true)
	if exit_code != 0:
		push_error("[BlendLoader] Blender export failed with exit code: " + str(exit_code))
		for line in output:
			print(line)
		return null

	if not FileAccess.file_exists(temp_glb):
		push_error("[BlendLoader] Exported GLB file was not created: " + temp_glb)
		return null

	print("[BlendLoader] Parsing exported GLB in Godot...")
	var gltf_doc = GLTFDocument.new()
	var gltf_state = GLTFState.new()
	var err = gltf_doc.append_from_file(temp_glb, gltf_state)
	
	if err != OK:
		push_error("[BlendLoader] GLTFDocument failed to parse GLB, error code: " + str(err))
		return null

	var scene_root = gltf_doc.generate_scene(gltf_state)
	
	# Clean up temp file
	DirAccess.remove_absolute(temp_glb)
	
	if scene_root:
		_make_materials_two_sided(scene_root)
	
	print("[BlendLoader] Successfully imported scene from .blend!")
	return scene_root

static func _make_materials_two_sided(node: Node) -> void:
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.material_override is BaseMaterial3D:
			(mi.material_override as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		if mi.mesh:
			for surf in range(mi.mesh.get_surface_count()):
				var mat = mi.get_surface_override_material(surf)
				if mat is BaseMaterial3D:
					(mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
				elif mat == null:
					var base_mat = mi.mesh.surface_get_material(surf)
					if base_mat is BaseMaterial3D:
						(base_mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
					elif base_mat == null:
						var new_mat = StandardMaterial3D.new()
						new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
						mi.set_surface_override_material(surf, new_mat)
	for child in node.get_children():
		_make_materials_two_sided(child)
