class_name MissileHitPayload
extends PayloadDriver

func intercept_payload(payload: HitPayload) -> void:
	payload.trajectory_movement_scene = trajectory_movement_scene
	payload.target_tracking_mode = target_tracking_mode
