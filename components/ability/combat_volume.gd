class_name CombatVolume
extends Area2D

signal collided(target: Node2D)

## Hitbox radius used when the ability's stats carry no AOE_RADIUS.
const DEFAULT_COLLISION_RADIUS: float = 10.0

## Set once per game run so a profile without AOE_RADIUS warns a single time.
static var _warned_missing_radius: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var combat_payload: CombatPayload
var collision_radius: float = DEFAULT_COLLISION_RADIUS
var spawn_position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var tracked_target_instance_id: int = 0


func initialize_volume(start_pos: Vector2, target_dir: Vector2, target_instance_id: int, incoming_payload: CombatPayload) -> void:
	combat_payload = incoming_payload
	spawn_position = start_pos
	tracked_target_instance_id = target_instance_id
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

	# The radius comes from the AOE_RADIUS stat, so read it before the shape is touched.
	var stats: Node = instance_from_id(combat_payload.stats_container_id)
	if is_instance_valid(stats):
		var radius: float = StatBonus.reach(stats as StatsContainer, Stat.Type.AOE_RADIUS)
		if radius > 0.0:
			collision_radius = radius
		elif not _warned_missing_radius:
			_warned_missing_radius = true
			push_warning("CombatVolume: AOE_RADIUS is 0 in the stats profile, using the default hitbox radius.")

	if is_instance_valid(collision_shape) and collision_shape.shape is CircleShape2D:
		collision_shape.shape = collision_shape.shape.duplicate()
		collision_shape.shape.radius = collision_radius


func _on_collision_detected(incoming_node: Node2D) -> void:		
	if incoming_node is HurtboxComponent and not incoming_node.is_player_hurtbox:
		incoming_node.take_hit(combat_payload)
		
	collided.emit(incoming_node)
	queue_free()
