class_name ChainLinkGeometry
extends SequencedGeometry

@export_group("Chaining Constraints")
@export var max_bounces: int = 4


## Geometry contract: the family of this geometry.
func get_family() -> StringName:
	return &"chain"


## Geometry contract: the stats that set how far this geometry reaches.
func get_reach_stats() -> Array[Stat.Type]:
	return [Stat.Type.CHAIN_RADIUS]


## Geometry contract: the stats that set how fast this geometry moves or advances.
func get_speed_stats() -> Array[Stat.Type]:
	return []


func get_query_shape(stats: StatsContainer) -> Shape2D:
	return super(stats)


func execute_geometry(query_results: Dictionary, final_payload: CombatPayload) -> void:
	var space_state := get_viewport().get_world_2d().direct_space_state
	var hit_nodes: Array = query_results.get("hit_nodes", [])

	# 1. Target Validation: If no initial target was caught in the radius sweep, abort instantly
	if hit_nodes.is_empty() or not space_state or not is_instance_valid(final_payload):
		delivery_finished.emit()
		return

	# 2. Extract Primary Target: Index 0 is mathematically closest
	var initial_target: HurtboxComponent = hit_nodes[0]
	if not is_instance_valid(initial_target):
		delivery_finished.emit()
		return

	# Everything the steps need is read now, at cast time
	var stats := _stats_of(final_payload)
	var chain_jump_radius: float = StatBonus.reach(stats, Stat.Type.CHAIN_RADIUS) if is_instance_valid(stats) else 400.0
	var delay := _sequence_delay(stats)

	# Chain state shared by the steps (a Dictionary, because a lambda copies plain locals): the last hit target and
	# where it was last seen, plus everything already hit
	var lookup_shape := CircleShape2D.new()
	lookup_shape.radius = chain_jump_radius
	var chain_state: Dictionary = {"target_id": initial_target.get_instance_id(), "position": initial_target.global_position}
	var excluded_instance_ids: Array[int] = [initial_target.get_instance_id()]

	var on_step := func(index: int) -> bool:
		# Step 0 is the primary target
		if index == 0:
			initial_target.take_hit(final_payload)
			return true

		# Later steps search from where the last hit target is now, or was last seen
		var last_target := instance_from_id(chain_state["target_id"]) as HurtboxComponent
		var last_position: Vector2 = chain_state["position"]
		if is_instance_valid(last_target):
			last_position = last_target.global_position
			chain_state["position"] = last_position
		var candidates := _enemy_hurtboxes_in(lookup_shape, last_position)
		var next_target: HurtboxComponent = null
		var shortest_dist_sq := chain_jump_radius * chain_jump_radius
		for candidate in candidates:
			# Do not hit the same enemy twice during a single cast
			if excluded_instance_ids.has(candidate.get_instance_id()):
				continue
			var dist_sq := last_position.distance_squared_to(candidate.global_position)
			if dist_sq < shortest_dist_sq:
				shortest_dist_sq = dist_sq
				next_target = candidate
		if not is_instance_valid(next_target):
			return false
		excluded_instance_ids.append(next_target.get_instance_id())
		next_target.take_hit(final_payload)
		chain_state["target_id"] = next_target.get_instance_id()
		chain_state["position"] = next_target.global_position
		return true

	_begin_sequence(max_bounces + 1, delay, on_step)
