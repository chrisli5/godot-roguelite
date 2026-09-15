class_name GeometryDriver
extends Node2D

## Virtual Method: Triggered by the parent wrapper's core timer loop execution pass.
## The geometry driver operates purely as a passive physical delivery agent.
func execute_delivery(current_speed: float, current_aoe_scale: float, final_payload: HitPayload) -> void:
	pass
