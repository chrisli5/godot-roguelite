@abstract
class_name GeometryDriver
extends Node

signal delivery_finished

## Defines the geometric shape of an ability. Responsible for the initial execution of an ability. 
@abstract
func execute_delivery(
	global_origin: Vector2, 
	target_direction: Vector2,
	current_speed: float, 
	current_aoe_scale: float, 
	final_payload: HitPayload
) -> void
