class_name Projectile
extends Area2D

signal collided(target: Node2D)

@export var movement_component: MovementComponent

@export var base_speed: float = 400.0
@export var acceleration: float = 99999.0
@export var friction: float = 0.0
@export var lifetime: float = 5.0

var hit_payload: HitPayload
var direction: Vector2 = Vector2.RIGHT
var spawn_position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var time_elapsed: float = 0.0


func _ready() -> void:
	global_position = spawn_position
	if direction != Vector2.ZERO:
		rotation = direction.angle()
		velocity = direction * base_speed
	
	area_entered.connect(_on_collision_detected)
	
	if not movement_component:
		push_error("Projectile: Missing required MovementComponent child node.")
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	time_elapsed += delta
	if time_elapsed >= lifetime:
		queue_free()
		return

	velocity = movement_component.calculate_velocity(
		velocity,
		direction,
		base_speed,
		acceleration,
		friction
	)

	global_position += velocity * delta


func _on_collision_detected(incoming_node: Node2D) -> void:
	if incoming_node == self or incoming_node.get_parent() == self:
		return
		
	# Check if the object we overlapped is a valid hurtbox
	if incoming_node is HurtboxComponent:
		var hurtbox = incoming_node as HurtboxComponent
		
		# Deliver the payload context straight to the receiver!
		hurtbox.take_hit(hit_payload)
		
	collided.emit(incoming_node)
	queue_free()
