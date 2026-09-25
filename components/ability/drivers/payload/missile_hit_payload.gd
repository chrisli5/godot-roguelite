class_name MissileCombatPayload
extends PayloadDriver

@export var trajectory_movement_scene: PackedScene

func intercept_payload(payload: CombatPayload) -> void:
	payload.trajectory_movement_scene = trajectory_movement_scene
