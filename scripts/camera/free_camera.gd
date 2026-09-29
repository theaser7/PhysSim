class_name FreeCamera
extends Camera3D

## Dual-mode 3D Camera: Smooth Orbit around target and Free-Fly WASD

enum CameraMode { ORBIT, FLY }

@export var mode: CameraMode = CameraMode.ORBIT
@export var orbit_target: Vector3 = Vector3(0.0, 1.0, 0.0)
@export var orbit_distance: float = 14.0
@export var orbit_sensitivity: float = 0.005
@export var fly_speed: float = 10.0
@export var fly_boost_multiplier: float = 2.5
@export var fly_sensitivity: float = 0.003

var _yaw: float = 0.6
var _pitch: float = -0.35
var _target_yaw: float = 0.6
var _target_pitch: float = -0.35
var _target_distance: float = 14.0
var _target_pivot: Vector3 = Vector3(0.0, 1.0, 0.0)

var _is_right_mouse_down: bool = false
var _is_middle_mouse_down: bool = false

func _ready() -> void:
	_target_distance = orbit_distance
	_target_pivot = orbit_target
	_update_orbit_transform(1.0)

func set_mode(new_mode: CameraMode) -> void:
	mode = new_mode
	SimState.camera_mode = "Orbit" if mode == CameraMode.ORBIT else "Fly"

func reset_view(target: Vector3 = Vector3(0.0, 1.0, 0.0), dist: float = 14.0) -> void:
	_target_pivot = target
	_target_distance = dist
	_target_yaw = 0.6
	_target_pitch = -0.35

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_right_mouse_down = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_middle_mouse_down = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mode == CameraMode.ORBIT:
				_target_distance = max(2.0, _target_distance * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mode == CameraMode.ORBIT:
				_target_distance = min(100.0, _target_distance * 1.1)

	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		if mode == CameraMode.ORBIT:
			if _is_right_mouse_down or _is_middle_mouse_down:
				if Input.is_key_pressed(KEY_SHIFT):
					# Pan pivot
					var pan_speed = _target_distance * 0.001
					var right = global_transform.basis.x
					var up = global_transform.basis.y
					_target_pivot -= (right * mm.relative.x - up * mm.relative.y) * pan_speed
				else:
					# Orbit rotation
					_target_yaw -= mm.relative.x * orbit_sensitivity
					_target_pitch -= mm.relative.y * orbit_sensitivity
					_target_pitch = clamp(_target_pitch, -1.45, 1.45)
		elif mode == CameraMode.FLY:
			if _is_right_mouse_down:
				_target_yaw -= mm.relative.x * fly_sensitivity
				_target_pitch -= mm.relative.y * fly_sensitivity
				_target_pitch = clamp(_target_pitch, -1.5, 1.5)

func _process(delta: float) -> void:
	_yaw = lerp(_yaw, _target_yaw, clamp(delta * 15.0, 0.0, 1.0))
	_pitch = lerp(_pitch, _target_pitch, clamp(delta * 15.0, 0.0, 1.0))

	if mode == CameraMode.ORBIT:
		orbit_distance = lerp(orbit_distance, _target_distance, clamp(delta * 10.0, 0.0, 1.0))
		orbit_target = orbit_target.lerp(_target_pivot, clamp(delta * 10.0, 0.0, 1.0))
		_update_orbit_transform(delta)
	elif mode == CameraMode.FLY:
		_process_fly_movement(delta)

func _update_orbit_transform(_delta: float) -> void:
	var rot_quat = Quaternion(Vector3.UP, _yaw) * Quaternion(Vector3.RIGHT, _pitch)
	var offset = rot_quat * Vector3(0, 0, orbit_distance)
	global_position = orbit_target + offset
	look_at(orbit_target, Vector3.UP)

func _process_fly_movement(delta: float) -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)

	var move_vec = Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move_vec -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		move_vec += global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		move_vec -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		move_vec += global_transform.basis.x
	if Input.is_key_pressed(KEY_E):
		move_vec += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move_vec -= Vector3.UP

	if move_vec.length_squared() > 0.001:
		var speed = fly_speed
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= fly_boost_multiplier
		global_position += move_vec.normalized() * (speed * delta)
