class_name HUDController
extends Control

## Blender-style scientific HUD controller managing telemetry, simulation transport, overlays, and presets

@export var camera: FreeCamera

# Telemetry labels (simulation physics metrics only)
@onready var telemetry_panel: PanelContainer = $TelemetryPanel
@onready var lbl_sim_time: Label = $TelemetryPanel/VBox/RowTime/Val
@onready var lbl_particles: Label = $TelemetryPanel/VBox/RowParticles/Val
@onready var lbl_energy: Label = $TelemetryPanel/VBox/RowEnergy/Val
@onready var lbl_wind: Label = $TelemetryPanel/VBox/RowWind/Val

# Overlays popover panel & toggles
@onready var btn_overlays: Button = $TopBar/HBox/BtnOverlays
@onready var overlays_panel: PanelContainer = $OverlaysPanel
@onready var check_vel_vectors: CheckBox = $OverlaysPanel/VBox/CheckVelVectors
@onready var check_acc_vectors: CheckBox = $OverlaysPanel/VBox/CheckAccVectors
@onready var check_streamlines: CheckBox = $OverlaysPanel/VBox/CheckStreamlines
@onready var check_cloth_stress: CheckBox = $OverlaysPanel/VBox/CheckClothStress

# Telemetry toggle button
@onready var btn_telemetry: Button = $TopBar/HBox/BtnTelemetry

# Playback transport controls (bottom-left)
@onready var btn_play_pause: Button = $TransportBar/HBox/BtnPlayPause
@onready var btn_step: Button = $TransportBar/HBox/BtnStep
@onready var btn_reset: Button = $TransportBar/HBox/BtnReset
@onready var slider_time_scale: HSlider = $TransportBar/HBox/TimeScaleBox/Slider
@onready var lbl_time_scale: Label = $TransportBar/HBox/TimeScaleBox/Val

# Physics parameters panel & sliders
@onready var physics_panel: PanelContainer = $PhysicsPanel
@onready var slider_gravity: HSlider = $PhysicsPanel/VBox/GravityBox/Slider
@onready var lbl_gravity: Label = $PhysicsPanel/VBox/GravityBox/HBox/Val

@onready var slider_wind_speed: HSlider = $PhysicsPanel/VBox/WindSpeedBox/Slider
@onready var lbl_wind_speed: Label = $PhysicsPanel/VBox/WindSpeedBox/HBox/Val

@onready var slider_wind_dir: HSlider = $PhysicsPanel/VBox/WindDirBox/Slider
@onready var lbl_wind_dir: Label = $PhysicsPanel/VBox/WindDirBox/HBox/Val

@onready var slider_viscosity: HSlider = $PhysicsPanel/VBox/ViscosityBox/Slider
@onready var lbl_viscosity: Label = $PhysicsPanel/VBox/ViscosityBox/HBox/Val

@onready var slider_wave_amp: HSlider = $PhysicsPanel/VBox/WaveAmpBox/Slider
@onready var lbl_wave_amp: Label = $PhysicsPanel/VBox/WaveAmpBox/HBox/Val

# Top workspace preset tabs & camera buttons
@onready var btn_preset_1: Button = $TopBar/HBox/WorkspaceTabs/BtnPreset1
@onready var btn_preset_2: Button = $TopBar/HBox/WorkspaceTabs/BtnPreset2
@onready var btn_preset_3: Button = $TopBar/HBox/WorkspaceTabs/BtnPreset3
@onready var btn_preset_4: Button = $TopBar/HBox/WorkspaceTabs/BtnPreset4
@onready var btn_import_model: Button = $TopBar/HBox/BtnImportModel
@onready var btn_cam_mode: Button = $TopBar/HBox/BtnCamMode
@onready var btn_reset_cam: Button = $TopBar/HBox/BtnResetCam

# Global model loader panel (accessible from any preset)
@onready var model_panel: PanelContainer = $ModelLoaderPanel

const ICON_PLAY = preload("res://icons/play.svg")
const ICON_PAUSE = preload("res://icons/pause.svg")

var _sim_time_accum: float = 0.0
var _style_tab_active: StyleBox
var _style_tab_inactive: StyleBox

func _ready() -> void:
	_style_tab_active = btn_preset_1.get_theme_stylebox("normal")
	_style_tab_inactive = btn_preset_2.get_theme_stylebox("normal")
	_connect_signals()
	_update_ui_from_state()

func _connect_signals() -> void:
	# Workspace tabs navigation
	btn_preset_1.pressed.connect(func(): SimState.set_preset(0))
	btn_preset_2.pressed.connect(func(): SimState.set_preset(1))
	btn_preset_3.pressed.connect(func(): SimState.set_preset(2))
	btn_preset_4.pressed.connect(func(): SimState.set_preset(3))

	# Popovers & Menus
	btn_import_model.pressed.connect(_toggle_model_menu)
	btn_overlays.pressed.connect(_toggle_overlays_menu)
	btn_telemetry.pressed.connect(_toggle_telemetry_menu)

	# Camera
	btn_cam_mode.pressed.connect(_toggle_camera_mode)
	btn_reset_cam.pressed.connect(_reset_camera)

	# Simulation Transport controls
	btn_play_pause.pressed.connect(_toggle_play_pause)
	btn_step.pressed.connect(func(): SimState.request_step())
	btn_reset.pressed.connect(_on_reset_requested)

	slider_time_scale.value_changed.connect(_on_time_scale_changed)
	slider_gravity.value_changed.connect(_on_gravity_changed)
	slider_wind_speed.value_changed.connect(_on_wind_speed_changed)
	slider_wind_dir.value_changed.connect(_on_wind_dir_changed)
	slider_viscosity.value_changed.connect(_on_viscosity_changed)
	slider_wave_amp.value_changed.connect(_on_wave_amp_changed)

	# Overlays checkboxes
	check_vel_vectors.toggled.connect(func(v): SimState.show_velocity_vectors = v)
	check_acc_vectors.toggled.connect(func(v): SimState.show_acceleration_vectors = v)
	check_streamlines.toggled.connect(func(v): SimState.show_streamlines = v)
	check_cloth_stress.toggled.connect(func(v): SimState.show_cloth_stress = v)

	SimState.preset_change_requested.connect(_on_preset_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				SimState.set_preset(0)
			KEY_2:
				SimState.set_preset(1)
			KEY_3:
				SimState.set_preset(2)
			KEY_4:
				SimState.set_preset(3)
			KEY_SPACE:
				_toggle_play_pause()
			KEY_R:
				_on_reset_requested()
			KEY_O:
				_toggle_overlays_menu()
			KEY_T:
				_toggle_telemetry_menu()
			KEY_M, KEY_I:
				_toggle_model_menu()

func _process(delta: float) -> void:
	if not SimState.is_paused:
		_sim_time_accum += delta * SimState.time_scale
	_update_telemetry()

func _update_telemetry() -> void:
	if not telemetry_panel.visible:
		return
	lbl_sim_time.text = "%.2f s" % _sim_time_accum

	var active_idx = SimState.active_preset_index
	match active_idx:
		0: # Ship & Ocean
			var ship_ke = 0.0
			var root = get_tree().current_scene
			if root and root.has_node("PresetContainer"):
				var pc = root.get_node("PresetContainer")
				if pc.get_child_count() > 0:
					var p1 = pc.get_child(0)
					if p1.has_node("Ship"):
						var ship = p1.get_node("Ship") as BuoyancyBody
						if ship:
							ship_ke = 0.5 * ship.mass * ship.linear_velocity.length_squared()
			lbl_particles.text = "1 (Rigid Body)"
			lbl_energy.text = "%.2f J" % ship_ke
		1: # SPH Fluid
			lbl_particles.text = "%d" % SimState.active_particle_count
			lbl_energy.text = "%.2f J" % SimState.total_kinetic_energy
		2: # Wind Tunnel
			var cloth_ke = 0.0
			var node_count = 180
			var root = get_tree().current_scene
			if root and root.has_node("PresetContainer"):
				var pc = root.get_node("PresetContainer")
				if pc.get_child_count() > 0:
					var p3 = pc.get_child(0)
					if p3.has_node("BannerCloth"):
						var cloth = p3.get_node("BannerCloth") as XPBDCloth
						if cloth and cloth.positions.size() > 0:
							node_count = cloth.positions.size()
							var pt_mass = cloth.total_mass / float(node_count)
							for v in cloth.velocities:
								cloth_ke += 0.5 * pt_mass * v.length_squared()
			lbl_particles.text = "%d (Cloth Nodes)" % node_count
			lbl_energy.text = "%.2f J" % cloth_ke
		3: # Sandbox
			lbl_particles.text = "%d" % SimState.active_particle_count
			lbl_energy.text = "%.2f J" % SimState.total_kinetic_energy

	lbl_wind.text = "%.1f m/s @ %d°" % [SimState.wind_speed, int(SimState.wind_direction_deg)]

func _update_ui_from_state() -> void:
	slider_time_scale.value = SimState.time_scale
	lbl_time_scale.text = "%.1fx" % SimState.time_scale

	slider_gravity.value = SimState.gravity.y
	lbl_gravity.text = "%.1f m/s²" % SimState.gravity.y

	slider_wind_speed.value = SimState.wind_speed
	lbl_wind_speed.text = "%.1f m/s" % SimState.wind_speed

	slider_wind_dir.value = SimState.wind_direction_deg
	lbl_wind_dir.text = "%d°" % int(SimState.wind_direction_deg)

	slider_viscosity.value = SimState.fluid_viscosity
	lbl_viscosity.text = "%.2f Pa·s" % SimState.fluid_viscosity

	slider_wave_amp.value = SimState.ocean_wave_amplitude
	lbl_wave_amp.text = "%.1f m" % SimState.ocean_wave_amplitude

	check_vel_vectors.button_pressed = SimState.show_velocity_vectors
	check_acc_vectors.button_pressed = SimState.show_acceleration_vectors
	check_streamlines.button_pressed = SimState.show_streamlines
	check_cloth_stress.button_pressed = SimState.show_cloth_stress

	_update_play_pause_button()
	_update_workspace_tabs(SimState.active_preset_index)

func _toggle_play_pause() -> void:
	SimState.toggle_pause()
	_update_play_pause_button()

func _update_play_pause_button() -> void:
	if SimState.is_paused:
		btn_play_pause.icon = ICON_PLAY
		btn_play_pause.text = ""
		btn_play_pause.tooltip_text = "Resume Simulation (Space)"
	else:
		btn_play_pause.icon = ICON_PAUSE
		btn_play_pause.text = ""
		btn_play_pause.tooltip_text = "Pause Simulation (Space)"

func _on_reset_requested() -> void:
	_sim_time_accum = 0.0
	SimState.request_reset()

func _toggle_model_menu() -> void:
	model_panel.visible = not model_panel.visible
	btn_import_model.modulate = Color(1.2, 1.2, 1.2) if model_panel.visible else Color(1.0, 1.0, 1.0)

func _toggle_overlays_menu() -> void:
	overlays_panel.visible = not overlays_panel.visible
	btn_overlays.modulate = Color(1.2, 1.2, 1.2) if overlays_panel.visible else Color(1.0, 1.0, 1.0)

func _toggle_telemetry_menu() -> void:
	telemetry_panel.visible = not telemetry_panel.visible
	btn_telemetry.modulate = Color(1.2, 1.2, 1.2) if telemetry_panel.visible else Color(1.0, 1.0, 1.0)

func _toggle_camera_mode() -> void:
	if camera:
		if camera.mode == FreeCamera.CameraMode.ORBIT:
			camera.set_mode(FreeCamera.CameraMode.FLY)
			btn_cam_mode.text = "CAM: FLY (WASD)"
		else:
			camera.set_mode(FreeCamera.CameraMode.ORBIT)
			btn_cam_mode.text = "CAM: ORBIT"

func _reset_camera() -> void:
	if camera:
		camera.reset_view()

func _on_time_scale_changed(val: float) -> void:
	SimState.time_scale = val
	lbl_time_scale.text = "%.1fx" % val

func _on_gravity_changed(val: float) -> void:
	SimState.gravity.y = val
	lbl_gravity.text = "%.1f m/s²" % val

func _on_wind_speed_changed(val: float) -> void:
	SimState.wind_speed = val
	lbl_wind_speed.text = "%.1f m/s" % val

func _on_wind_dir_changed(val: float) -> void:
	SimState.wind_direction_deg = val
	lbl_wind_dir.text = "%d°" % int(val)

func _on_viscosity_changed(val: float) -> void:
	SimState.fluid_viscosity = val
	lbl_viscosity.text = "%.2f Pa·s" % val

func _on_wave_amp_changed(val: float) -> void:
	SimState.ocean_wave_amplitude = val
	lbl_wave_amp.text = "%.1f m" % val

func _on_preset_changed(idx: int) -> void:
	_sim_time_accum = 0.0
	_update_workspace_tabs(idx)

func _update_workspace_tabs(idx: int) -> void:
	var tabs = [btn_preset_1, btn_preset_2, btn_preset_3, btn_preset_4]
	for i in range(tabs.size()):
		var tab = tabs[i]
		if i == idx:
			if _style_tab_active:
				tab.add_theme_stylebox_override("normal", _style_tab_active)
				tab.add_theme_stylebox_override("hover", _style_tab_active)
				tab.add_theme_stylebox_override("pressed", _style_tab_active)
			tab.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
			tab.modulate = Color(1.15, 1.15, 1.2, 1.0)
		else:
			if _style_tab_inactive:
				tab.add_theme_stylebox_override("normal", _style_tab_inactive)
				tab.add_theme_stylebox_override("hover", _style_tab_inactive)
				tab.add_theme_stylebox_override("pressed", _style_tab_inactive)
			tab.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
			tab.modulate = Color(0.9, 0.9, 0.9, 1.0)
