class_name CollectorComponent
extends Area2D

signal payload_collected(payload: PickupPayload)


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(entered_area: Area2D) -> void:
	if not is_instance_valid(entered_area):
		return
		
	if entered_area is CollectibleComponent:
		var collectible = entered_area as CollectibleComponent
		var payload: PickupPayload = collectible.get_pickup_payload()
		
		if is_instance_valid(payload) and payload is PickupPayload:
			payload_collected.emit(payload)
			collectible.register_collection()
