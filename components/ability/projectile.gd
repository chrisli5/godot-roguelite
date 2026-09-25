class_name Projectile
extends Area2D

signal collided(target: Node2D)

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var hit_payload: HitPayload
var movement_strategy: MovementStrategy = null
var movement_speed: float = 400.0
var collision_radius: float = 10.0
var lifetime: float = 5.0

var direction: Vector2 = Vector2.RIGHT 
var spawn_position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var time_elapsed: float = 0.0


func _ready() -> void:
	global_position = spawn_position
	if direction != Vector2.ZERO:
		rotation = direction.angle()
		velocity = direction * movement_speed
	
	area_entered.connect(_on_collision_detected)
	
	if not is_instance_valid(hit_payload):
		return
	
	if is_instance_valid(hit_payload.base_texture):
		if is_instance_valid(sprite):
			sprite.texture = hit_payload.base_texture

	if is_instance_valid(collision_shape):
		if collision_shape.shape is CircleShape2D:
			collision_shape.shape = collision_shape.shape.duplicate()
			(collision_shape.shape as CircleShape2D).radius = collision_radius
			
	if  hit_payload.trajectory_movement_scene is PackedScene:
		var move_inst = hit_payload.trajectory_movement_scene.instantiate() as MovementStrategy
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
		if is_instance_valid(hit_payload) and is_instance_valid(hit_payload.tracked_target_node):
			tracking_target = hit_payload.tracked_target_node

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


func initialize_projectile(start_pos: Vector2, target_dir: Vector2, incoming_payload: HitPayload) -> void:
	hit_payload = incoming_payload
	spawn_position = start_pos
	direction = target_dir.normalized()
	
	# Extract and scale metrics safely out of the passport's stats link
	if is_instance_valid(hit_payload):
		var stats = hit_payload.stats_source
		if is_instance_valid(stats):
			movement_speed = stats.get_stat_value(Stat.Type.PROJECTILE_MOVEMENT_SPEED, 400.0)
			collision_radius = stats.get_stat_value(Stat.Type.AOE_RADIUS, 10.0)
			lifetime = stats.get_stat_value(Stat.Type.DURATION, 5.0) # Pulled out of resource dynamically!


func _on_collision_detected(incoming_node: Node2D) -> void:
	if incoming_node == self or incoming_node.get_parent() == self:
		return
	if incoming_node is HurtboxComponent:
		incoming_node.take_hit(hit_payload)
	collided.emit(incoming_node)
	queue_free()
