class_name SPHGrid
extends RefCounted

## High-performance Spatial Hash Grid with flat linked-lists and O(1) deduplication

var cell_size: float = 0.35
var inv_cell_size: float = 1.0 / 0.35
var table_size: int = 4096

# Flat linked-list buckets (zero per-frame array allocations)
var _head: PackedInt32Array = []
var _next: PackedInt32Array = []

# Stamp-based visited check for O(1) bucket deduplication
var _visited_stamp: PackedInt32Array = []
var _query_id: int = 1

const PRIME_X: int = 73856093
const PRIME_Y: int = 19349663
const PRIME_Z: int = 83492791

func _init(p_cell_size: float = 0.35, p_table_size: int = 4096) -> void:
	cell_size = p_cell_size
	inv_cell_size = 1.0 / p_cell_size
	table_size = p_table_size
	_head.resize(table_size)
	_head.fill(-1)
	_visited_stamp.resize(table_size)
	_visited_stamp.fill(0)
	_next.resize(1024)

func clear() -> void:
	_head.fill(-1)

func _hash_coords(cx: int, cy: int, cz: int) -> int:
	var h = (cx * PRIME_X) ^ (cy * PRIME_Y) ^ (cz * PRIME_Z)
	return posmod(h, table_size)

func insert(particle_idx: int, pos: Vector3) -> void:
	if particle_idx >= _next.size():
		_next.resize(max(particle_idx + 256, _next.size() * 2))
	var cx = int(floor(pos.x * inv_cell_size))
	var cy = int(floor(pos.y * inv_cell_size))
	var cz = int(floor(pos.z * inv_cell_size))
	var bucket = _hash_coords(cx, cy, cz)
	_next[particle_idx] = _head[bucket]
	_head[bucket] = particle_idx

## Returns array of potential neighbor particle indices within 27 adjacent cells
func get_candidate_neighbors(pos: Vector3) -> Array:
	var cx = int(floor(pos.x * inv_cell_size))
	var cy = int(floor(pos.y * inv_cell_size))
	var cz = int(floor(pos.z * inv_cell_size))

	_query_id += 1
	if _query_id > 1000000000:
		_visited_stamp.fill(0)
		_query_id = 1

	var candidates: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var bucket = _hash_coords(cx + dx, cy + dy, cz + dz)
				if _visited_stamp[bucket] == _query_id:
					continue
				_visited_stamp[bucket] = _query_id

				var p = _head[bucket]
				while p != -1:
					candidates.append(p)
					p = _next[p]

	return candidates
