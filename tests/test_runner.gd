extends Node

const WindField = preload("res://scripts/physics/wind_field.gd")
const OceanSystem = preload("res://scripts/physics/ocean_system.gd")
const XPBDCloth = preload("res://scripts/physics/xpbd_cloth.gd")
const SPHGrid = preload("res://scripts/physics/sph_grid.gd")
const SPHFluid = preload("res://scripts/physics/sph_fluid.gd")
const STLLoader = preload("res://scripts/loaders/stl_loader.gd")

func _ready() -> void:
	print("\n==========================================")
	print("       RUNNING PHYSSIM TEST SUITE         ")
	print("==========================================")
	
	var passed = 0
	var failed = 0

	if test_wind_field():
		print("[PASS] Wind Field & Aerodynamics")
		passed += 1
	else:
		print("[FAIL] Wind Field & Aerodynamics")
		failed += 1

	if test_ocean_system():
		print("[PASS] Ocean Gerstner Wave Math")
		passed += 1
	else:
		print("[FAIL] Ocean Gerstner Wave Math")
		failed += 1

	if test_xpbd_cloth():
		print("[PASS] XPBD Dynamic Cloth")
		passed += 1
	else:
		print("[FAIL] XPBD Dynamic Cloth")
		failed += 1

	if test_sph_fluid():
		print("[PASS] SPH Fluid & Spatial Hashing")
		passed += 1
	else:
		print("[FAIL] SPH Fluid & Spatial Hashing")
		failed += 1

	if test_stl_welding():
		print("[PASS] STL Loader & Vertex Welding")
		passed += 1
	else:
		print("[FAIL] STL Loader & Vertex Welding")
		failed += 1

	if test_preset_scenes():
		print("[PASS] All Preset Scenes Instantiation")
		passed += 1
	else:
		print("[FAIL] All Preset Scenes Instantiation")
		failed += 1

	if await test_ship_stability():
		print("[PASS] Ship Hydrodynamic Stability & Center of Mass")
		passed += 1
	else:
		print("[FAIL] Ship Hydrodynamic Stability & Center of Mass")
		failed += 1

	if test_sandbox_preset():
		print("[PASS] Sandbox Preset (No Ocean Waves Floor Clipping)")
		passed += 1
	else:
		print("[FAIL] Sandbox Preset (No Ocean Waves Floor Clipping)")
		failed += 1

	if await test_step_frame_reset():
		print("[PASS] Simulation Step & Pause State Management")
		passed += 1
	else:
		print("[FAIL] Simulation Step & Pause State Management")
		failed += 1

	if await test_live_ui_and_sliders():
		print("[PASS] Blender UI, Global Model Import Button, Overlays Popover & Sliders")
		passed += 1
	else:
		print("[FAIL] Blender UI, Global Model Import Button, Overlays Popover & Sliders")
		failed += 1

	print("==========================================")
	print("TESTS COMPLETED: %d PASSED, %d FAILED" % [passed, failed])
	print("==========================================\n")

	get_tree().quit(0 if failed == 0 else 1)

func test_wind_field() -> bool:
	var wind = WindField.new()
	add_child(wind)
	SimState.wind_speed = 10.0
	SimState.wind_direction_deg = 90.0 # East (X+)
	
	var v = wind.get_wind_velocity(Vector3(0, 5, 0))
	if v.length() < 1.0:
		printerr("Wind velocity magnitude is too low: ", v)
		return false

	# Aerodynamic force on flat surface facing wind
	var p0 = Vector3(0, 0, 0)
	var p1 = Vector3(0, 2, 0)
	var p2 = Vector3(2, 0, 0)
	var aero = wind.compute_aerodynamic_force(p0, p1, p2, Vector3.ZERO)
	var f: Vector3 = aero["force"]
	if f.length() < 0.01:
		printerr("Aerodynamic force should be non-zero on surface facing wind: ", f)
		return false

	wind.queue_free()
	return true

func test_ocean_system() -> bool:
	var ocean = OceanSystem.new()
	add_child(ocean)
	ocean._sim_time = 1.0
	SimState.ocean_wave_amplitude = 1.0

	var norm = ocean.get_wave_normal(Vector3(5, 0, 5))

	if abs(norm.length() - 1.0) > 0.01:
		printerr("Ocean normal is not normalized: ", norm.length())
		return false

	if norm.y <= 0.0:
		printerr("Ocean normal Y should be positive upwards: ", norm)
		return false

	ocean.queue_free()
	return true

func test_xpbd_cloth() -> bool:
	var cloth = XPBDCloth.new()
	cloth.cloth_width = 2.0
	cloth.cloth_height = 2.0
	cloth.resolution_x = 5
	cloth.resolution_y = 4
	add_child(cloth)
	cloth._init_cloth_grid()

	if cloth.positions.size() != 20:
		printerr("Expected 20 cloth particles, got: ", cloth.positions.size())
		return false

	# Verify side corners are pinned and middle top particle is unpinned
	if cloth.inv_masses[0] != 0.0 or cloth.inv_masses[4] != 0.0:
		printerr("Top side corners must be pinned (inv_mass == 0)")
		return false
	if cloth.inv_masses[2] <= 0.0:
		printerr("Middle cloth particle must NOT be pinned (inv_mass > 0)")
		return false

	if cloth.constraints.is_empty():
		printerr("No constraints generated for cloth")
		return false

	cloth._step_simulation(0.016)

	if cloth.vertex_stress.size() != 20:
		printerr("Vertex stress array size mismatch")
		return false

	cloth.queue_free()
	return true

func test_sph_fluid() -> bool:
	var grid = SPHGrid.new(0.35, 1024)
	grid.insert(0, Vector3(0, 0, 0))
	grid.insert(1, Vector3(0.1, 0.1, 0.1))
	grid.insert(2, Vector3(5, 5, 5))

	var nbrs = grid.get_candidate_neighbors(Vector3(0, 0, 0))
	if not nbrs.has(0) or not nbrs.has(1):
		printerr("Spatial hash failed to find adjacent neighbors")
		return false

	# Test bucket deduplication on small table size collision
	var small_grid = SPHGrid.new(1.0, 4)
	small_grid.insert(0, Vector3(0, 0, 0))
	var candidates = small_grid.get_candidate_neighbors(Vector3(0, 0, 0))
	var count_0 = 0
	for c in candidates:
		if c == 0:
			count_0 += 1
	if count_0 != 1:
		printerr("SPHGrid duplicated candidate neighbor on bucket collision! Count: ", count_0)
		return false

	var sph = SPHFluid.new()
	sph.max_particles = 300
	sph.initial_particle_count = 250
	sph.smoothing_radius = 0.35
	sph._init_kernel_constants()
	sph._grid = SPHGrid.new(sph.smoothing_radius, 1024)
	sph._spawn_initial_particles()

	if sph.positions.size() != 250:
		printerr("SPH failed to spawn initial particles: ", sph.positions.size())
		return false

	sph._step_sph(0.016)

	if sph.densities[0] <= 0.0:
		printerr("SPH density calculation failed, got: ", sph.densities[0])
		return false

	# Benchmark SPH steps performance with realistic 250-particle workload
	var t0 = Time.get_ticks_msec()
	for step in range(30):
		sph._step_sph(0.016)
	var elapsed = Time.get_ticks_msec() - t0
	if elapsed > 450:
		printerr("SPH steps took too long: %d ms for 30 steps of 250 particles" % elapsed)
		return false

	sph.queue_free()
	return true

func test_stl_welding() -> bool:
	# Test empty vertices returns null gracefully without crashing
	var empty_mesh = STLLoader.weld_and_build_mesh(PackedVector3Array())
	if empty_mesh != null:
		printerr("Expected null for empty vertices")
		return false

	var raw = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)
	])

	var mesh = STLLoader.weld_and_build_mesh(raw)
	if mesh == null:
		printerr("Failed to weld and build mesh")
		return false

	var arrays = mesh.surface_get_arrays(0)
	var unique_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	if unique_verts.size() != 4:
		printerr("Expected 4 welded vertices, got: ", unique_verts.size())
		return false

	if indices.size() != 6:
		printerr("Expected 6 indices, got: ", indices.size())
		return false

	# Test two-sided material assignment on generated surfaces
	var mat = mesh.surface_get_material(0)
	if not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_DISABLED:
		printerr("STL mesh material must be two-sided (CULL_DISABLED)")
		return false

	# Test Blender Z-up to Godot Y-up orientation conversion
	var ship_stl = STLLoader.load_stl_file("res://pirate_ship_LowPoly.stl")
	if ship_stl:
		var aabb = ship_stl.get_aabb()
		# Height (masts) should be along Y (> 8.0) and length along Z (> 8.0)
		if aabb.size.y < 8.0 or aabb.size.z < 8.0:
			printerr("STL Z-up orientation conversion failed, got AABB: ", aabb)
			return false

	return true

func test_ship_stability() -> bool:
	var p1_scene = load("res://scenes/presets/preset1_ship_ocean.tscn")
	if p1_scene == null:
		printerr("Failed to load preset1 scene")
		return false
	var inst = p1_scene.instantiate()
	add_child(inst)
	var ship = inst.get_node_or_null("Ship") as BuoyancyBody
	if ship == null:
		printerr("Ship node missing in preset 1")
		inst.queue_free()
		return false

	if ship.center_of_mass.y > -0.5:
		printerr("Ship center of mass should be low in hull, got: ", ship.center_of_mass.y)
		inst.queue_free()
		return false

	if ship.probe_points.size() < 15:
		printerr("Ship should have multi-probe distributed buoyancy points across beam")
		inst.queue_free()
		return false

	if ship.righting_stiffness < 500.0 or ship.roll_pitch_damping < 10.0:
		printerr("Ship righting stiffness or roll damping insufficient")
		inst.queue_free()
		return false

	# Simulate 60 physics frames and ensure ship stays stably upright in waves
	for f in range(60):
		await get_tree().physics_frame
		var up_alignment = ship.global_transform.basis.y.dot(Vector3.UP)
		if up_alignment < 0.7:
			printerr("Ship capsized! Alignment to UP is: ", up_alignment)
			inst.queue_free()
			return false

	# Test righting recovery when artificially perturbed with a 35-degree roll tilt
	ship.rotate_object_local(Vector3.FORWARD, deg_to_rad(35.0))
	for f in range(60):
		await get_tree().physics_frame
	var recovered_alignment = ship.global_transform.basis.y.dot(Vector3.UP)
	if recovered_alignment < 0.8:
		printerr("Ship failed to right itself after 35-degree tilt, alignment: ", recovered_alignment)
		inst.queue_free()
		return false

	inst.queue_free()
	return true

func test_sandbox_preset() -> bool:
	var p4_scene = load("res://scenes/presets/preset4_sandbox.tscn")
	if p4_scene == null:
		printerr("Failed to load preset4 scene")
		return false
	var inst = p4_scene.instantiate()
	if inst.get_node_or_null("OceanSystem") != null:
		printerr("Sandbox preset must NOT have OceanSystem (ocean waves clipping floor)")
		inst.free()
		return false
	if inst.get_node_or_null("Floor") == null:
		printerr("Sandbox preset must have solid Floor")
		inst.free()
		return false
	inst.free()
	return true

func test_preset_scenes() -> bool:
	var presets = [
		"res://scenes/presets/preset1_ship_ocean.tscn",
		"res://scenes/presets/preset2_sph_fluid.tscn",
		"res://scenes/presets/preset3_wind_tunnel.tscn",
		"res://scenes/presets/preset4_sandbox.tscn",
		"res://scenes/main.tscn"
	]

	for path in presets:
		var scene = load(path)
		if scene == null:
			printerr("Failed to load scene: ", path)
			return false
		var inst = scene.instantiate()
		if inst == null:
			printerr("Failed to instantiate scene: ", path)
			return false
		inst.free()

	return true

func test_step_frame_reset() -> bool:
	SimState.is_paused = true
	SimState.request_step()
	if not SimState.step_frame_requested:
		printerr("step_frame_requested was not set to true after request_step")
		return false

	# Wait for physics frame to finish
	await get_tree().physics_frame
	await get_tree().process_frame

	if SimState.step_frame_requested:
		printerr("step_frame_requested was NOT reset to false after physics frame!")
		return false

	return true
	
func test_live_ui_and_sliders() -> bool:
	var main_scene = load("res://scenes/main.tscn")
	if not main_scene:
		printerr("Failed to load res://scenes/main.tscn")
		return false

	var main_inst = main_scene.instantiate()
	add_child(main_inst)

	await get_tree().process_frame
	await get_tree().process_frame

	var hud = main_inst.get_node_or_null("HUD") as HUDController
	if not hud:
		printerr("HUD node missing from main.tscn")
		main_inst.queue_free()
		return false

	# Test slider updates and label formatting
	hud.slider_gravity.value = -12.4
	hud._on_gravity_changed(-12.4)
	if hud.lbl_gravity.text != "-12.4 m/s²":
		printerr("Gravity slider label failed to update! Value: ", hud.lbl_gravity.text)
		main_inst.queue_free()
		return false

	hud.slider_wind_speed.value = 16.5
	hud._on_wind_speed_changed(16.5)
	if hud.lbl_wind_speed.text != "16.5 m/s":
		printerr("Wind speed slider label failed to update! Value: ", hud.lbl_wind_speed.text)
		main_inst.queue_free()
		return false

	hud.slider_wind_dir.value = 90.0
	hud._on_wind_dir_changed(90.0)
	if hud.lbl_wind_dir.text != "90°":
		printerr("Wind dir slider label failed to update! Value: ", hud.lbl_wind_dir.text)
		main_inst.queue_free()
		return false

	hud.slider_viscosity.value = 0.50
	hud._on_viscosity_changed(0.50)
	if hud.lbl_viscosity.text != "0.50 Pa·s":
		printerr("Viscosity slider label failed to update! Value: ", hud.lbl_viscosity.text)
		main_inst.queue_free()
		return false

	hud.slider_wave_amp.value = 1.8
	hud._on_wave_amp_changed(1.8)
	if hud.lbl_wave_amp.text != "1.8 m":
		printerr("Wave amp slider label failed to update! Value: ", hud.lbl_wave_amp.text)
		main_inst.queue_free()
		return false

	# Test popover toggles
	hud._toggle_overlays_menu()
	if not hud.overlays_panel.visible:
		printerr("Overlays panel failed to open")
		main_inst.queue_free()
		return false

	hud._toggle_overlays_menu()
	if hud.overlays_panel.visible:
		printerr("Overlays panel failed to close")
		main_inst.queue_free()
		return false

	hud._toggle_telemetry_menu()
	if hud.telemetry_panel.visible:
		printerr("Telemetry panel failed to close on toggle")
		main_inst.queue_free()
		return false

	hud._toggle_telemetry_menu()
	if not hud.telemetry_panel.visible:
		printerr("Telemetry panel failed to reopen on toggle")
		main_inst.queue_free()
		return false

	# Test SVG icons present on transport buttons
	if hud.btn_play_pause.icon == null or hud.btn_play_pause.text != "":
		printerr("Play/Pause button should have SVG icon and empty text")
		main_inst.queue_free()
		return false
	if hud.btn_reset.icon == null or hud.btn_step.icon == null:
		printerr("Reset/Step buttons should have SVG icons")
		main_inst.queue_free()
		return false

	# Test presets cycle and workspace tab stylebox swapping in live scene
	for p in range(4):
		SimState.set_preset(p)
		await get_tree().process_frame
		await get_tree().physics_frame
		# Verify the active tab gets active stylebox
		var active_tab = [hud.btn_preset_1, hud.btn_preset_2, hud.btn_preset_3, hud.btn_preset_4][p]
		if active_tab.get_theme_stylebox("normal") != hud._style_tab_active:
			printerr("Preset tab %d did not receive active stylebox!" % p)
			main_inst.queue_free()
			return false

		# Verify Global Model Import button can open ModelDialog from ANY preset
		hud.model_panel.visible = false
		hud._toggle_model_menu()
		if not hud.model_panel.visible:
			printerr("Global import button failed to open ModelDialog in preset %d!" % p)
			main_inst.queue_free()
			return false
		hud._toggle_model_menu()
		if hud.model_panel.visible:
			printerr("Global import button failed to close ModelDialog in preset %d!" % p)
			main_inst.queue_free()
			return false

	main_inst.queue_free()
	return true
