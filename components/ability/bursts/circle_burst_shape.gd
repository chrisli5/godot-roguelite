class_name CircleBurstShape
extends BurstShape
## A circle of radius AOE_RADIUS * radius_multiplier around the burst origin.

@export var radius_multiplier: float = 1.0
@export_group("Physics Hardware Configuration")
@export_flags_2d_physics var enemy_collision_mask: int = 4
@export var max_results_buffer: int = 32

## Set once per game run so a missing AOE_RADIUS warns a single time.
static var _warned_missing_radius: bool = false


func find_targets(origin: Vector2, stats: StatsContainer, space_state: PhysicsDirectSpaceState2D, exclude_instance_id: int) -> Array[HurtboxComponent]:
	var targets: Array[HurtboxComponent] = []
	var radius := 0.0
	if is_instance_valid(stats):
		radius = StatBonus.reach(stats, Stat.Type.AOE_RADIUS) * radius_multiplier
	if radius <= 0.0:
		if not _warned_missing_radius:
			_warned_missing_radius = true
			push_warning("CircleBurstShape: AOE_RADIUS is missing or 0, so the burst has no reach.")
		return targets

	var circle := CircleShape2D.new()
	circle.radius = radius
	var intersections := SpatialQuery.query_shape_intersections(
		space_state, circle, origin, enemy_collision_mask, max_results_buffer
	)
	for result in intersections:
		var hurtbox := result.get("collider") as HurtboxComponent
		if hurtbox == null or hurtbox.is_player_hurtbox:
			continue
		if hurtbox.get_instance_id() == exclude_instance_id:
			continue
		targets.append(hurtbox)
	return targets
