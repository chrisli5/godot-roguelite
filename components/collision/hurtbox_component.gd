# res://components/collision/hurtbox_component.gd
class_name HurtboxComponent
extends Area2D

signal hit_received(payload: CombatPayload)

func take_hit(payload: CombatPayload) -> void:
	print("[HURTBOX] payload recieved.")
	if not is_instance_valid(payload):
		return

	hit_received.emit(payload)
