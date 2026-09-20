@abstract
class_name MovementStrategy
extends Node

@abstract
func calculate_velocity(
	current_velocity: Vector2,
	target_velocity: Vector2,
	max_speed: float, 
	acceleration: float, 
	friction: float,
	time_elapsed: float
) -> Vector2
