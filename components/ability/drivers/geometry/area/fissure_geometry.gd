# res://components/ability/drivers/geometry/fissure_geometry.gd
class_name FissureGeometry
extends GeometryDriver

@export_group("Fissure Scaling")
## Total number of sequential step explosions created in a line per cast
@export var fissure_steps: int = 3
## Distance interval step size in pixels between each cluster strike
@export var distance_step: float = 70.0
## Size of the first circle explosion zone block
@export var starting_radius: float = 30.0
## Sizing multiplier added per step to expand the crash zone outward
@export var expansion_rate_per_step: float = 15.0


## Geometry contract: the family of this geometry.
func get_family() -> StringName:
	return &"area_instant"


## Geometry contract: the stats that set how far this geometry reaches.
func get_reach_stats() -> Array[Stat.Type]:
	return [Stat.Type.AOE_RADIUS]


## Geometry contract: the stats that set how fast this geometry moves or advances.
func get_speed_stats() -> Array[Stat.Type]:
	return []


func get_query_shape(_stats: StatsContainer) -> Shape2D:
	return null # Returns null so the initial loop skips, allowing custom multi-step queries below


func execute_geometry(query_results: Dictionary, final_payload: CombatPayload) -> void:
	var space_state := get_viewport().get_world_2d().direct_space_state
	if not space_state:
		delivery_finished.emit()
		return

	var global_origin: Vector2 = query_results.get("origin", Vector2.ZERO)
	
	var target_direction := Vector2.RIGHT
	var player = instance_from_id(EventBus.active_player_instance_id) as Player
	if is_instance_valid(player):
		target_direction = player.velocity.normalized() if player.velocity != Vector2.ZERO else Vector2.RIGHT

	var stats := _stats_of(final_payload)
	var first_radius := _get_area_radius(stats, starting_radius)
	var step_shape := CircleShape2D.new()

	# Execute sequential queries on the physics server directly for step tracking line rules
	for step in range(fissure_steps):
		var calculated_distance := (step + 1) * distance_step
		var target_strike_point := global_origin + (target_direction * calculated_distance)
		
		var growth_factor := step * expansion_rate_per_step
		step_shape.radius = (first_radius + growth_factor)
		
		for hurtbox in _enemy_hurtboxes_in(step_shape, target_strike_point):
			hurtbox.take_hit(final_payload)

	delivery_finished.emit()
