class_name HUDController
extends Control

## Scientific HUD controller managing telemetry, simulation controls, and preset switching

@export var camera: FreeCamera

# Telemetry labels
@onready var lbl_fps: Label = $TelemetryPanel/VBox/LblFPS
@onready var lbl_wind: Label = $TelemetryPanel/VBox/LblWind
@onready var lbl_particles: Label = $TelemetryPanel/VBox/LblParticles
@onready var lbl_energy: Label = $TelemetryPanel/VBox/LblEnergy
@onready var lbl_status: Label = $TelemetryPanel/VBox/LblStatus

# Control buttons & sliders
@onready var btn_play_pause: Button = $ControlBar/HBox/BtnPlayPause
@onready var btn_step: Button = $ControlBar/HBox/BtnStep
@onready var btn_reset: Button = $ControlBar/HBox/BtnReset
@onready var slider_time_scale: HSlider = $ControlBar/HBox/TimeScaleBox/Slider
@onready var lbl_time_scale: Label = $ControlBar/HBox/TimeScaleBox/Val

@onready var slider_gravity: HSlider = $PhysicsPanel/VBox/GravityBox/Slider
@onready var lbl_gravity: Label = $PhysicsPanel/VBox/GravityBox/Val

@onready var slider_wind_speed: HSlider = $PhysicsPanel/VBox/WindSpeedBox/Slider
@onready var lbl_wind_speed: Label = $PhysicsPanel/VBox/WindSpeedBox/Val

@onready var slider_wind_dir: HSlider = $PhysicsPanel/VBox/WindDirBox/Slider
@onready var lbl_wind_dir: Label = $PhysicsPanel/VBox/WindDirBox/Val

@onready var slider_viscosity: HSlider = $PhysicsPanel/VBox/ViscosityBox/Slider
@onready var lbl_viscosity: Label = $PhysicsPanel/VBox/ViscosityBox/Val

@onready var slider_wave_amp: HSlider = $PhysicsPanel/VBox/WaveAmpBox/Slider
@onready var lbl_wave_amp: Label = $PhysicsPanel/VBox/WaveAmpBox/Val

# Visualization check buttons
@onready var check_vel_vectors: CheckBox = $VisToggles/HBox/CheckVelVectors
@onready var check_acc_vectors: CheckBox = $VisToggles/HBox/CheckAccVectors
@onready var check_streamlines: CheckBox = $VisToggles/HBox/CheckStreamlines
@onready var check_cloth_stress: CheckBox = $VisToggles/HBox/CheckClothStress

# Top navigation
@onready var btn_preset_1: Button = $TopBar/HBox/BtnPreset1
@onready var btn_preset_2: Button = $TopBar/HBox/BtnPreset2
@onready var btn_preset_3: Button = $TopBar/HBox/BtnPreset3
@onready var btn_preset_4: Button = $TopBar/HBox/BtnPreset4
@onready var btn_cam_mode: Button = $TopBar/HBox/BtnCamMode
@onready var btn_reset_cam: Button = $TopBar/HBox/BtnResetCam

# Sandbox model loader panel
@onready var model_panel: PanelContainer = $ModelLoaderPanel

func _ready() -> void:
	_connect_signals()
	_update_ui_from_state()

func _connect_signals() -> void:
	# Navigation
	btn_preset_1.pressed.connect(func(): SimState.set_preset(0))
	btn_preset_2.pressed.connect(func(): SimState.set_preset(1))
	btn_preset_3.pressed.connect(func(): SimState.set_preset(2))
	btn_preset_4.pressed.connect(func(): SimState.set_preset(3))

	btn_cam_mode.pressed.connect(_toggle_camera_mode)
	btn_reset_cam.pressed.connect(_reset_camera)

	# Controls
	btn_play_pause.pressed.connect(_toggle_play_pause)
	btn_step.pressed.connect(func(): SimState.request_step())
	btn_reset.pressed.connect(func(): SimState.request_reset())

	slider_time_scale.value_changed.connect(_on_time_scale_changed)
	slider_gravity.value_changed.connect(_on_gravity_changed)
	slider_wind_speed.value_changed.connect(_on_wind_speed_changed)
	slider_wind_dir.value_changed.connect(_on_wind_dir_changed)
	slider_viscosity.value_changed.connect(_on_viscosity_changed)
	slider_wave_amp.value_changed.connect(_on_wave_amp_changed)

	check_vel_vectors.toggled.connect(func(v): SimState.show_velocity_vectors = v)
	check_acc_vectors.toggled.connect(func(v): SimState.show_acceleration_vectors = v)
	check_streamlines.toggled.connect(func(v): SimState.show_streamlines = v)
	check_cloth_stress.toggled.connect(func(v): SimState.show_cloth_stress = v)

	SimState.preset_change_requested.connect(_on_preset_changed)

func _process(_delta: float) -> void:
	_update_telemetry()

func _update_telemetry() -> void:
	lbl_fps.text = "FPS: %d (%.1f ms)" % [int(SimState.fps), SimState.frame_time_ms]
	lbl_wind.text = "Wind: %.1f m/s @ %d deg" % [SimState.wind_speed, int(SimState.wind_direction_deg)]
	lbl_particles.text = "Particles / Verts: %d" % SimState.active_particle_count
	lbl_energy.text = "Kinetic Energy: %.2f J" % SimState.total_kinetic_energy
	
	if SimState.is_paused:
		lbl_status.text = "STATUS: PAUSED"
		lbl_status.modulate = Color(1.0, 0.6, 0.2)
	else:
		lbl_status.text = "STATUS: RUNNING (%.1fx)" % SimState.time_scale
		lbl_status.modulate = Color(0.2, 0.9, 0.4)

func _update_ui_from_state() -> void:
	slider_time_scale.value = SimState.time_scale
	lbl_time_scale.text = "%.1fx" % SimState.time_scale

	slider_gravity.value = SimState.gravity.y
	lbl_gravity.text = "%.1f m/s^2" % SimState.gravity.y

	slider_wind_speed.value = SimState.wind_speed
	lbl_wind_speed.text = "%.1f m/s" % SimState.wind_speed

	slider_wind_dir.value = SimState.wind_direction_deg
	lbl_wind_dir.text = "%d deg" % int(SimState.wind_direction_deg)

	slider_viscosity.value = SimState.fluid_viscosity
	lbl_viscosity.text = "%.2f" % SimState.fluid_viscosity

	slider_wave_amp.value = SimState.ocean_wave_amplitude
	lbl_wave_amp.text = "%.1f m" % SimState.ocean_wave_amplitude

	check_vel_vectors.button_pressed = SimState.show_velocity_vectors
	check_acc_vectors.button_pressed = SimState.show_acceleration_vectors
	check_streamlines.button_pressed = SimState.show_streamlines
	check_cloth_stress.button_pressed = SimState.show_cloth_stress

	btn_play_pause.text = "PAUSE [||]" if not SimState.is_paused else "PLAY [>]"

func _toggle_play_pause() -> void:
	SimState.toggle_pause()
	btn_play_pause.text = "PAUSE [||]" if not SimState.is_paused else "PLAY [>]"

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
	lbl_gravity.text = "%.1f m/s^2" % val

func _on_wind_speed_changed(val: float) -> void:
	SimState.wind_speed = val
	lbl_wind_speed.text = "%.1f m/s" % val

func _on_wind_dir_changed(val: float) -> void:
	SimState.wind_direction_deg = val
	lbl_wind_dir.text = "%d deg" % int(val)

func _on_viscosity_changed(val: float) -> void:
	SimState.fluid_viscosity = val
	lbl_viscosity.text = "%.2f" % val

func _on_wave_amp_changed(val: float) -> void:
	SimState.ocean_wave_amplitude = val
	lbl_wave_amp.text = "%.1f m" % val

func _on_preset_changed(idx: int) -> void:
	model_panel.visible = (idx == 3)
	# Highlight active preset button
	btn_preset_1.modulate = Color(1.2, 1.2, 1.2) if idx == 0 else Color(0.7, 0.7, 0.7)
	btn_preset_2.modulate = Color(1.2, 1.2, 1.2) if idx == 1 else Color(0.7, 0.7, 0.7)
	btn_preset_3.modulate = Color(1.2, 1.2, 1.2) if idx == 2 else Color(0.7, 0.7, 0.7)
	btn_preset_4.modulate = Color(1.2, 1.2, 1.2) if idx == 3 else Color(0.7, 0.7, 0.7)
