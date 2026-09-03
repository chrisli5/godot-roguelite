# res://components/collision/hurtbox_component.gd
class_name HurtboxComponent
extends Area2D

signal hit_received(payload: HitPayload)

func take_hit(payload: HitPayload) -> void:
	if not is_instance_valid(payload):
		return

	hit_received.emit(payload)
