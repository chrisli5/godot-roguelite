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
	
	velocity = movement_component.calculate_velocity(velocity, max_speed, acceleration, friction)
	move_and_slide()
		
	
