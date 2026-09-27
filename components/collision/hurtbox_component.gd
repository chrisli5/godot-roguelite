# res://components/collision/hurtbox_component.gd
class_name HurtboxComponent
extends Area2D

signal hit_received(payload: CombatPayload)

var owner_entity: Entity = null
var is_player_hurtbox: bool:
	get:
		return owner_entity is Player


func take_hit(payload: CombatPayload) -> void:
	if not is_instance_valid(payload):
		return

	hit_received.emit(payload)
