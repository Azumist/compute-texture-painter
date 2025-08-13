extends Camera3D

@export var mouse_sensitivity := 1.0
@export var camera_distance := 2.0
@export var min_max_distance := Vector2(1.0, 3.0)
@export var target_global_pos := Vector3.ZERO
@export var zoom_speed := 6.0

const zoom_step := 0.35

var is_holding_rmb: bool
var yaw: float = 0.0
var pitch: float = 0.0
var target_dist: float

func _ready() -> void:
	target_dist = camera_distance

func _unhandled_input(event):
	if event is InputEventMouseButton:
		is_holding_rmb = event.pressed && event.button_index == MOUSE_BUTTON_RIGHT

		if event.pressed && event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_dist -= zoom_step

		if event.pressed && event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_dist += zoom_step

		target_dist = clampf(target_dist, min_max_distance.x, min_max_distance.y)
	
	if is_holding_rmb && event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * mouse_sensitivity * 0.01
		pitch += motion.relative.y * mouse_sensitivity * 0.01
		pitch = clamp(pitch, -PI/2 + 0.1, PI/2 - 0.1)

func _process(delta: float) -> void:
	camera_distance = lerpf(camera_distance, target_dist, 1.0 - exp(-zoom_speed * delta))

	var cos_pitch := cos(pitch)
	var spherical_to_cart := camera_distance * Vector3(sin(yaw) * cos_pitch, sin(pitch), cos(yaw) * cos_pitch)
	global_position = target_global_pos + spherical_to_cart
	look_at(target_global_pos, Vector3.UP)
