class_name MissileHitPayload
extends PayloadDriver

@export var trajectory_movement_scene: PackedScene

func intercept_payload(payload: HitPayload) -> void:
	payload.trajectory_movement_scene = trajectory_movement_scene
