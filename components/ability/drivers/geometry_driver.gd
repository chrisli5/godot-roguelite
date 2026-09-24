@abstract
class_name GeometryDriver
extends Node

@warning_ignore("unused_signal")
signal delivery_finished

## Defines the geometric shape of an ability. Responsible for the initial execution of an ability. 
@abstract
func execute_geometry(
	global_origin: Vector2, 
	target_direction: Vector2,
	stats: StatsContainer,
	final_payload: HitPayload
) -> void
