@abstract
class_name GeometryDriver
extends Node

@warning_ignore("unused_signal")
signal delivery_finished

## Set once per game run so a profile without AOE_RADIUS warns a single time.
static var _warned_area_fallback: bool = false

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


## The StatsContainer a payload was cast from, or null when the payload or the container is gone.
func _stats_of(payload: CombatPayload) -> StatsContainer:
	if not is_instance_valid(payload):
		return null
	return instance_from_id(payload.stats_container_id) as StatsContainer


## Enemy hurtboxes overlapping `shape` at `global_pos`, through the shared query helper. Empty when there is no physics space.
func _enemy_hurtboxes_in(shape: Shape2D, global_pos: Vector2, exclude_instance_id: int = 0) -> Array[HurtboxComponent]:
	var viewport := get_viewport()
	if viewport == null or viewport.get_world_2d() == null:
		return []
	return SpatialQuery.query_enemy_hurtboxes(viewport.get_world_2d().direct_space_state, shape, global_pos, exclude_instance_id)


## Geometry families. Every concrete geometry declares one through get_family().
const FAMILIES: Array[StringName] = [&"moving_hitbox", &"area_instant", &"area_stepped", &"chain", &"timed"]


## Which family this geometry belongs to (one of FAMILIES). Every concrete geometry must override it; an empty family means the geometry has not declared its contract.
func get_family() -> StringName:
	return &""


## The stats that set how far this geometry reaches. Earth scales these. Empty means none.
func get_reach_stats() -> Array[Stat.Type]:
	return []


## The stats that set how fast this geometry moves or advances. Wind scales these. Empty means it has no speed concept.
func get_speed_stats() -> Array[Stat.Type]:
	return []


## Reach of an area geometry: the AOE_RADIUS stat, or `fallback` (with a one-time warning) when it is missing or 0.
func _get_area_radius(stats: StatsContainer, fallback: float) -> float:
	if is_instance_valid(stats):
		var radius: float = StatBonus.reach(stats, Stat.Type.AOE_RADIUS)
		if radius > 0.0:
			return radius
	if not _warned_area_fallback:
		_warned_area_fallback = true
		push_warning("GeometryDriver: AOE_RADIUS is missing or 0, using the fallback reach.")
	return fallback
