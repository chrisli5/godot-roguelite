class_name VectorMovementStrategy
extends MovementStrategy

@export_range(0.0, 1.0) var acceleration_weight: float = 0.2


func calculate_velocity(
	current_velocity: Vector2,
	target_direction: Vector2,
	max_speed: float,
	_current_global_position: Vector2,
	_time_elapsed: float,
	_target_node: Node2D = null
) -> Vector2:
	
	if target_direction != Vector2.ZERO:
		return current_velocity.lerp(target_direction * max_speed, acceleration_weight)
	else:
		return current_velocity.lerp(Vector2.ZERO, acceleration_weight)
