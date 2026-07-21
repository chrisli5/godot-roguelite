class_name KeyboardMovementComponent
extends MovementComponent

func calculate_velocity(current_velocity: Vector2, max_speed: float, acceleration: float, friction: float) -> Vector2:
	var direction: Vector2 = Vector2.ZERO
	
	direction.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	direction.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	
	var target_velocity: Vector2 = direction.normalized() * max_speed
	
	if target_velocity != Vector2.ZERO:
		return current_velocity.lerp(target_velocity, acceleration)
	else:
		return current_velocity.lerp(Vector2.ZERO, friction)
