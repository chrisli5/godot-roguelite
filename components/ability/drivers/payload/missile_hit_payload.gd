class_name MissileHitPayload
extends PayloadDriver

@export var target_tracking_mode: HitPayload.TargetTrackingMode = HitPayload.TargetTrackingMode.STATIC_VECTOR
@export var trajectory_movement_scene: PackedScene

func intercept_payload(payload: HitPayload) -> void:
	payload.trajectory_movement_scene = trajectory_movement_scene
	payload.target_tracking_mode = target_tracking_mode
	payload.tracked_target_node = payload.caster
