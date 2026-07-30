class_name ExperiencePickupComponent
extends CollectibleComponent

@export_group("XP Settings")
@export var experience_value: float = 25.0


func get_pickup_payload() -> PickupPayload:
	var payload = PickupPayload.new()
	payload.type = "experience"
	payload.value = experience_value
	return payload
