class_name Enemy
extends Entity

var enemy_data: EnemyData:
	get:
		return entity_data as EnemyData

var current_player_instance_id: int = 0


func _physics_process(_delta: float) -> void:
	_handle_movement_physics()


func _handle_movement_physics() -> void:
	if not movement_strategy or not stats_container:
		return
	
	var max_speed = stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED)
	var look_direction = Vector2.RIGHT.rotated(rotation)
	
	if EventBus.active_player_instance_id > 0:
		current_player_instance_id = EventBus.active_player_instance_id

	velocity = movement_strategy.calculate_velocity(
		velocity,
		look_direction,
		max_speed,
		global_position,
		0.0,
		current_player_instance_id
	)
	
	move_and_slide()
