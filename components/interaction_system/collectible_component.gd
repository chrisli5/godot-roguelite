@abstract
class_name CollectibleComponent
extends Area2D

signal collected


func _ready() -> void:
	collision_layer = 0
	monitoring = false


@abstract
func get_pickup_payload() -> PickupPayload


func register_collection() -> void:
	monitorable = false
	collected.emit()
