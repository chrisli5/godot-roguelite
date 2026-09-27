class_name CombatVolume
extends Area2D

signal collided(target: Node2D)

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var combat_payload: CombatPayload
var collision_radius: float = 10.0
var spawn_position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT


func initialize_volume(start_pos: Vector2, target_dir: Vector2, incoming_payload: CombatPayload) -> void:
	combat_payload = incoming_payload
	spawn_position = start_pos
	direction = target_dir.normalized()


func _ready() -> void:
	global_position = spawn_position
	if direction != Vector2.ZERO:
		rotation = direction.angle()
		
	area_entered.connect(_on_collision_detected)
	
	if not is_instance_valid(combat_payload):
		return
		
	if is_instance_valid(sprite) and combat_payload.base_texture is Texture2D:
		sprite.texture = combat_payload.base_texture

	if is_instance_valid(collision_shape) and collision_shape.shape is CircleShape2D:
		collision_shape.shape = collision_shape.shape.duplicate()
		collision_shape.shape.radius = collision_radius
	
	var stats: Node = null
	if combat_payload.stats_container_id > 0:
		stats = instance_from_id(combat_payload.stats_container_id) as Node
	
	var has_stats := is_instance_valid(stats)
	collision_radius = stats.get_stat_value(Stat.Type.AOE_RADIUS, 10.0) if has_stats else 10.0


func _on_collision_detected(incoming_node: Node2D) -> void:		
	if incoming_node is HurtboxComponent and not incoming_node.is_player_hurtbox:
		incoming_node.take_hit(combat_payload)
		
	collided.emit(incoming_node)
	queue_free()
