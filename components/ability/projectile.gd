class_name Projectile
extends CombatVolume

var movement_strategy: MovementStrategy = null
var movement_speed: float = 400.0
var lifetime: float = 5.0
var velocity: Vector2 = Vector2.ZERO
var time_elapsed: float = 0.0


# Override initialization to pull projectile-exclusive stats
func initialize_projectile(start_pos: Vector2, target_dir: Vector2, incoming_payload: CombatPayload) -> void:
	initialize_volume(start_pos, target_dir, incoming_payload)
	
	if is_instance_valid(combat_payload) and is_instance_valid(combat_payload.stats_source):
		var stats = combat_payload.stats_source
		movement_speed = stats.get_stat_value(Stat.Type.PROJECTILE_MOVEMENT_SPEED, 400.0)
		lifetime = stats.get_stat_value(Stat.Type.DURATION, 5.0)


func _ready() -> void:
	super()
	velocity = direction * movement_speed
	
	if is_instance_valid(combat_payload) and combat_payload.trajectory_movement_scene is PackedScene:
		var move_inst = combat_payload.trajectory_movement_scene.instantiate() as MovementStrategy
		if move_inst:
			add_child(move_inst)
			movement_strategy = move_inst


func _physics_process(delta: float) -> void:
	time_elapsed += delta
	if time_elapsed >= lifetime:
		queue_free()
		return

	if is_instance_valid(movement_strategy):
		var tracking_target: Node2D = null
		if is_instance_valid(combat_payload) and is_instance_valid(combat_payload.tracked_target_node):
			tracking_target = combat_payload.tracked_target_node
			
		velocity = movement_strategy.calculate_velocity(
			velocity,
			direction, 
			movement_speed,
			global_position,
			time_elapsed,
			tracking_target
		)
		if velocity != Vector2.ZERO:
			rotation = velocity.angle()
	else:
		velocity = direction * movement_speed

	global_position += velocity * delta
