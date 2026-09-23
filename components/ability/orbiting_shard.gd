class_name OrbitingShard
extends Area2D

signal collided(target: Node2D)

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var hit_payload: HitPayload
var collision_radius: float = 1.0


func _ready() -> void:	
	area_entered.connect(_on_collision_detected)
	
	if not is_instance_valid(hit_payload):
		return
	
	if is_instance_valid(hit_payload.base_texture):
		if is_instance_valid(sprite):
			sprite.texture = hit_payload.base_texture

	if is_instance_valid(collision_shape):
		var radius_override: float = collision_radius
		if collision_shape.shape is CircleShape2D:
			collision_shape.shape.radius = radius_override
			#collision_shape.shape = collision_shape.shape.duplicate()
			#(collision_shape.shape as CircleShape2D).radius = radius_override


func _on_collision_detected(incoming_node: Node2D) -> void:
	if incoming_node == self or incoming_node.get_parent() == self:
		return
	if incoming_node is HurtboxComponent:
		incoming_node.take_hit(hit_payload)
	collided.emit(incoming_node)
	queue_free()
