@abstract
class_name PayloadDriver
extends Node

## Acts upon a transient "hit_payload" object generated during ability execution, injecting it with custom properties defined in this driver.
@export var target_tracking_mode: HitPayload.TargetTrackingMode = HitPayload.TargetTrackingMode.STATIC_VECTOR
@export var trajectory_movement_scene: PackedScene

@abstract
func intercept_payload(payload: HitPayload) -> void
