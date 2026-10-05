class_name Projectile
extends CombatVolume

var movement_strategy: MovementStrategy = null
var movement_speed: float = 0.0
var lifetime: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var time_elapsed: float = 0.0


func _ready() -> void:
	super()
	
	var stats: Node = instance_from_id(combat_payload.stats_container_id)
	var has_stats := is_instance_valid(stats)
	movement_speed = stats.get_final_stat_value(Stat.Type.PROJECTILE_MOVEMENT_SPEED) if has_stats else 400.0
	lifetime = stats.get_final_stat_value(Stat.Type.DURATION) if has_stats else 1.0
	velocity = direction * movement_speed
	
	if is_instance_valid(combat_payload) and combat_payload.trajectory_movement_scene is PackedScene:
		var move_inst = combat_payload.trajectory_movement_scene.instantiate() as MovementStrategy
		if move_inst:
			add_child(move_inst)
			movement_strategy = move_inst
			
		if movement_strategy is BoomerangMovementStrategy:
			movement_strategy.return_phase_entered.connect(_on_return_phase_entered)
			tracked_target_instance_id = combat_payload.caster_instance_id


func _physics_process(delta: float) -> void:
	time_elapsed += delta
	if time_elapsed >= lifetime:
		queue_free()
		return

	if is_instance_valid(movement_strategy):
		velocity = movement_strategy.calculate_velocity(
			velocity,
			direction, 
			movement_speed,
			global_position,
			time_elapsed,
			tracked_target_instance_id
		)
		if velocity != Vector2.ZERO:
			rotation = velocity.angle()
	else:
		velocity = direction * movement_speed

	global_position += velocity * delta


func _on_return_phase_entered() -> void:
	set_collision_mask_value(2, true)
