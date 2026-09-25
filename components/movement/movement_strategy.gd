@abstract
class_name MovementStrategy
extends Node

@abstract
func calculate_velocity(
	current_velocity: Vector2,
	target_direction: Vector2,
	max_speed: float,
	current_global_position: Vector2,
	time_elapsed: float,
	target_node: Node2D = null
) -> Vector2
