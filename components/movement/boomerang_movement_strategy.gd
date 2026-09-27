class_name BoomerangMovementStrategy
extends MovementStrategy

signal return_phase_entered

@export_group("Boomerang Physics Constants")
@export var deceleration_rate: float = 850.0
@export var return_acceleration: float = 1200.0
@export var maximum_outward_duration: float = 0.6

var is_returning: bool = false
var _cached_outward_heading: Vector2 = Vector2.ZERO


func calculate_velocity(
	current_velocity: Vector2,
	target_direction: Vector2,
	max_speed: float,
	current_global_position: Vector2,
	time_elapsed: float,
	target_node_id: int = 0,
) -> Vector2:

	var fixed_delta := get_physics_process_delta_time()
	if not is_returning:
		if _cached_outward_heading == Vector2.ZERO:
			_cached_outward_heading = target_direction if target_direction != Vector2.ZERO else Vector2.RIGHT
			
		var current_speed := current_velocity.length() if current_velocity != Vector2.ZERO else max_speed
		var speed_reduction := deceleration_rate * fixed_delta
		var next_speed := current_speed - speed_reduction

		if next_speed <= 10.0 or time_elapsed >= maximum_outward_duration:
			is_returning = true
			return_phase_entered.emit()

			if target_node_id > 0:
				var target_node: Node2D = instance_from_id(target_node_id)
				if is_instance_valid(target_node):
					return (target_node.global_position - current_global_position).normalized() * 50.0
			return -_cached_outward_heading * 50.0
			
		return _cached_outward_heading * next_speed
		
	else:
		var return_heading := -_cached_outward_heading
		if target_node_id > 0:
			var target_node: Node2D = instance_from_id(target_node_id)
			if is_instance_valid(target_node):
				return_heading = (target_node.global_position - current_global_position).normalized()
			
		var current_speed := current_velocity.length()
		var approach_speed := current_speed + (return_acceleration * fixed_delta)
		var clamped_speed := minf(approach_speed, max_speed * 1.5)
		
		return return_heading * clamped_speed
