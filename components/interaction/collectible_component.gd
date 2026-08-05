@abstract
class_name CollectibleComponent
extends Area2D

signal pickup_collected


@abstract
func get_pickup_payload() -> PickupPayload


func register_collection() -> void:
	set_deferred("monitorable", false)
	pickup_collected.emit()
