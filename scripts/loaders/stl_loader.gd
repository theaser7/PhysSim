class_name STLLoader
extends RefCounted

## Binary and ASCII STL file parser with vertex welding and topological reconstruction

static func load_stl_file(file_path: String, convert_z_up: bool = true) -> ArrayMesh:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("[STLLoader] Failed to open file: " + file_path)
		return null

	var buffer = file.get_buffer(file.get_length())
	file.close()

	if buffer.size() < 6:
		push_error("[STLLoader] File too small to be valid STL")
		return null

	# Check if binary or ASCII
	if is_binary_stl(buffer):
		return parse_binary_stl(buffer, convert_z_up)
	else:
		return parse_ascii_stl(buffer.get_string_from_utf8(), convert_z_up)

static func is_binary_stl(buffer: PackedByteArray) -> bool:
	if buffer.size() < 84:
		return false
	
	# In binary STL, bytes 80..83 is uint32 triangle count
	var sp = StreamPeerBuffer.new()
	sp.data_array = buffer
	sp.seek(80)
	var tri_count = sp.get_u32()
	var expected_size = 84 + (tri_count * 50)
	
	if buffer.size() == expected_size:
		return true

	# Check for "solid" keyword at start
	var header = buffer.slice(0, 5).get_string_from_utf8().to_lower()
	if header == "solid":
		return false

	return true

static func parse_binary_stl(buffer: PackedByteArray, convert_z_up: bool = true) -> ArrayMesh:
	var sp = StreamPeerBuffer.new()
	sp.data_array = buffer
	sp.seek(80)
	var num_triangles = sp.get_u32()

	var raw_vertices: PackedVector3Array = []
	raw_vertices.resize(num_triangles * 3)
	var raw_idx = 0

	for i in range(num_triangles):
		# Normal vector (3x float32)
		sp.get_float()
		sp.get_float()
		sp.get_float()

		# Vertex 1, 2, 3
		for v in range(3):
			var vx = sp.get_float()
			var vy = sp.get_float()
			var vz = sp.get_float()
			if convert_z_up:
				# Convert Blender / CAD Z-up to Godot Y-up: (-x, z, y) so Mast is +Y, Bow is +Z, Stern is -Z
				raw_vertices[raw_idx] = Vector3(-vx, vz, vy)
			else:
				raw_vertices[raw_idx] = Vector3(vx, vy, vz)
			raw_idx += 1

		# Attribute byte count (uint16)
		sp.get_u16()

	return weld_and_build_mesh(raw_vertices)

static func parse_ascii_stl(text: String, convert_z_up: bool = true) -> ArrayMesh:
	var raw_vertices: PackedVector3Array = []
	var lines = text.split("\n")

	for line in lines:
		var trimmed = line.strip_edges()
		if trimmed.begins_with("vertex"):
			var parts = trimmed.split(" ", false)
			if parts.size() >= 4:
				var vx = parts[1].to_float()
				var vy = parts[2].to_float()
				var vz = parts[3].to_float()
				if convert_z_up:
					raw_vertices.append(Vector3(-vx, vz, vy))
				else:
					raw_vertices.append(Vector3(vx, vy, vz))

	return weld_and_build_mesh(raw_vertices)

## Welds duplicate vertices using spatial hashing, builds indices, and generates smooth normals
static func weld_and_build_mesh(raw_vertices: PackedVector3Array) -> ArrayMesh:
	var raw_count = raw_vertices.size()
	if raw_count < 3:
		return null
	var unique_vertices: PackedVector3Array = []
	var indices: PackedInt32Array = []
	var vertex_lookup: Dictionary = {}

	# Scale factor for quantization (1mm precision)
	var quant: float = 1000.0

	for i in range(raw_count):
		var v = raw_vertices[i]
		var key = "%d_%d_%d" % [int(round(v.x * quant)), int(round(v.y * quant)), int(round(v.z * quant))]

		if vertex_lookup.has(key):
			indices.append(vertex_lookup[key])
		else:
			var new_idx = unique_vertices.size()
			vertex_lookup[key] = new_idx
			unique_vertices.append(v)
			indices.append(new_idx)

	var num_unique = unique_vertices.size()
	if num_unique < 3 or indices.size() < 3:
		push_warning("[STLLoader] Insufficient vertices or indices to construct a mesh surface")
		return null

	var normals: PackedVector3Array = []
	normals.resize(num_unique)
	normals.fill(Vector3.ZERO)

	var tri_count = indices.size() / 3
	for t in range(tri_count):
		var i0 = indices[t * 3 + 0]
		var i1 = indices[t * 3 + 1]
		var i2 = indices[t * 3 + 2]

		var v0 = unique_vertices[i0]
		var v1 = unique_vertices[i1]
		var v2 = unique_vertices[i2]

		var face_normal = (v1 - v0).cross(v2 - v0)
		normals[i0] += face_normal
		normals[i1] += face_normal
		normals[i2] += face_normal

	for i in range(num_unique):
		normals[i] = normals[i].normalized()

	# Create ArrayMesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = unique_vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Default two-sided material to eliminate backface culling transparency
	var default_mat = StandardMaterial3D.new()
	default_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, default_mat)
	
	return mesh
