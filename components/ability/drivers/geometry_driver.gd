@abstract
class_name GeometryDriver
extends Node

@warning_ignore("unused_signal")
signal delivery_finished

## Defines the geometric shape of an ability. Responsible for the initial execution of an ability. 
@abstract
func execute_geometry(query_results: Dictionary, final_payload: CombatPayload) -> void


func get_query_shape(stats: StatsContainer) -> Shape2D:
	var circle := CircleShape2D.new()
	if is_instance_valid(stats):
		circle.radius = stats.get_final_stat_value(Stat.Type.QUERY_RADIUS)
	else:
		circle.radius = 200.0
	return circle
