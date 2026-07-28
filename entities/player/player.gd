class_name Player
extends Entity


func _physics_process(_delta: float) -> void:
	_handle_movement_physics()


func _handle_movement_physics() -> void:
	if not movement_component:
		return
	
	var max_speed: float = 10.0
	var acceleration: float = 1.0
	var friction: float = 1.0
	
	if stats_container:
		max_speed = stats_container.get_stat_value(Stat.Type.SPEED, max_speed)
		acceleration = stats_container.get_stat_value(Stat.Type.ACCELERATION, acceleration)
		friction = stats_container.get_stat_value(Stat.Type.FRICTION, friction)
		
	var direction: Vector2 = Vector2.ZERO
	
	direction.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	direction.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	
	var target_velocity: Vector2 = direction.normalized()
	
	velocity = movement_component.calculate_velocity(velocity, target_velocity, max_speed, acceleration, friction)
	move_and_slide()
		
	
