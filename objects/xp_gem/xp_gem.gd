class_name XPGem
extends Node2D

@export_group("Components")
@export var experience_pickup_component: ExperiencePickupComponent


func _ready() -> void:
	if is_instance_valid(experience_pickup_component):
		experience_pickup_component.pickup_collected.connect(_on_pickup_collected)


func _on_pickup_collected(_by_entity: Node) -> void:
	queue_free()
