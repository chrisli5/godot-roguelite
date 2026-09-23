class_name Projectile
extends Area2D

signal collided(target: Node2D)

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var hit_payload: HitPayload
var movement_strategy: MovementStrategy = null

var movement_speed: float = 400.0
var acceleration: float = 99999.0
var friction: float = 0.0
var lifetime: float = 5.0

var direction: Vector2 = Vector2.RIGHT # Acts as the persistent static direction fallback
var spawn_position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var collision_radius: float = 10.0
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

	# --- UNIFIED TARGET DIRECTION MEDIATION ---
	# Default to our static initial direction vector assigned at spawning
	var current_frame_target_direction := direction
	if not is_instance_valid(hit_payload):
		return
	
	# If the passport holds a valid tracked enemy node, recalculate the vector dynamically
	if hit_payload.target_tracking_mode == HitPayload.TargetTrackingMode.REALTIME_NODE:
		if is_instance_valid(hit_payload.tracked_target_node):
			var enemy: Node2D = hit_payload.tracked_target_node
			current_frame_target_direction = (enemy.global_position - global_position).normalized()
	# --- STRATEGY DELEGATION ---
	if is_instance_valid(movement_strategy):
		# Push-model parameter injection: Hand over the final processed vector context
		velocity = movement_strategy.calculate_velocity(
			velocity,
			current_frame_target_direction, # Dynamically adjusted vector
			movement_speed,
			acceleration,
			friction,
			time_elapsed
		)
		if velocity != Vector2.ZERO:
			rotation = velocity.angle()
	else:
		# Standard fallback straight projectile path
		velocity = current_frame_target_direction * movement_speed

	global_position += velocity * delta


func _on_collision_detected(incoming_node: Node2D) -> void:
	if incoming_node == self or incoming_node.get_parent() == self:
		return
	if incoming_node is HurtboxComponent:
		incoming_node.take_hit(hit_payload)
	collided.emit(incoming_node)
	queue_free()
