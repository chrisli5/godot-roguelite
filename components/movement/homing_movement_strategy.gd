class_name HomingMovementStrategy
extends MovementStrategy

@export_group("Homing Physics Controls")
@export var steering_force: float = 0.15
@export var tracking_frame_throttle: int = 3

var _current_frame_tick: int = 0
var _cached_homing_direction: Vector2 = Vector2.ZERO


func calculate_velocity(
	current_velocity: Vector2,
	target_direction: Vector2,
	max_speed: float,
	current_global_position: Vector2,
	_time_elapsed: float,
	target_node: Node2D = null
) -> Vector2:
	
	if not is_instance_valid(target_node):
		var fallback_heading = _cached_homing_direction if _cached_homing_direction != Vector2.ZERO else target_direction
		return current_velocity.lerp(fallback_heading * max_speed, steering_force)

	_current_frame_tick += 1
	if _current_frame_tick >= tracking_frame_throttle or _cached_homing_direction == Vector2.ZERO:
		_current_frame_tick = 0
		
		# Pristine, stateless vector tracking pass using pure incoming parameters!
		_cached_homing_direction = (target_node.global_position - current_global_position).normalized()

	var target_velocity = _cached_homing_direction * max_speed
	return current_velocity.lerp(target_velocity, steering_force)
