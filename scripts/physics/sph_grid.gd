class_name SPHGrid
extends RefCounted

## Spatial Hash Grid for O(N) neighbor searches in 3D SPH fluid simulation

var cell_size: float = 0.35
var inv_cell_size: float = 1.0 / 0.35
var table_size: int = 4096

# Hash table storing particle indices per bucket
var _grid: Array[Array] = []

const PRIME_X: int = 73856093
const PRIME_Y: int = 19349663
const PRIME_Z: int = 83492791

func _init(p_cell_size: float = 0.35, p_table_size: int = 4096) -> void:
	cell_size = p_cell_size
	inv_cell_size = 1.0 / p_cell_size
	table_size = p_table_size
	_grid.resize(table_size)
	for i in range(table_size):
		_grid[i] = []

func clear() -> void:
	for i in range(table_size):
		_grid[i].clear()

func _hash_coords(cx: int, cy: int, cz: int) -> int:
	var h = (cx * PRIME_X) ^ (cy * PRIME_Y) ^ (cz * PRIME_Z)
	return posmod(h, table_size)

func insert(particle_idx: int, pos: Vector3) -> void:
	var cx = int(floor(pos.x * inv_cell_size))
	var cy = int(floor(pos.y * inv_cell_size))
	var cz = int(floor(pos.z * inv_cell_size))
	var bucket = _hash_coords(cx, cy, cz)
	_grid[bucket].append(particle_idx)

## Returns array of potential neighbor particle indices within 27 adjacent cells
func get_candidate_neighbors(pos: Vector3) -> Array:
	var cx = int(floor(pos.x * inv_cell_size))
	var cy = int(floor(pos.y * inv_cell_size))
	var cz = int(floor(pos.z * inv_cell_size))

	var candidates: Array = []
	var visited_buckets: Array[int] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var bucket = _hash_coords(cx + dx, cy + dy, cz + dz)
				if visited_buckets.has(bucket):
					continue
				visited_buckets.append(bucket)
				var cell_particles = _grid[bucket]
				var count = cell_particles.size()
				for k in range(count):
					candidates.append(cell_particles[k])

	return candidates
