class_name VelocityMovementComponent
extends MovementComponent

func calculate_velocity(current_velocity: Vector2, target_velocity: Vector2, max_speed: float, acceleration: float, friction: float) -> Vector2:	
	if target_velocity != Vector2.ZERO:
		return current_velocity.lerp(target_velocity * max_speed, acceleration)
	else:
		return current_velocity.lerp(Vector2.ZERO, friction)
