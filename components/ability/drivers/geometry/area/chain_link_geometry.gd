class_name ChainLinkGeometry
extends GeometryDriver

@export_group("Physics Hardware Configuration")
@export_flags_2d_physics var enemy_collision_mask: int = 4
@export var max_results_buffer: int = 32

@export_group("Chaining Constraints")
@export var max_bounces: int = 4


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

	# Extract chain jump stats from dynamic runtime memory banks
	var stats = instance_from_id(final_payload.stats_container_id)
	var has_stats := is_instance_valid(stats)
	var chain_jump_radius: float = stats.get_final_stat_value(Stat.Type.CHAIN_RADIUS, 400.0) if has_stats else 400.0

	# Apply damage payload to the primary target
	initial_target.take_hit(final_payload)

	# 3. Procedural Secondary Bouncing Engine Loop
	var active_search_position := initial_target.global_position
	var lookup_shape := CircleShape2D.new()
	var excluded_instance_ids: Array[int] = [initial_target.get_instance_id()]

	for bounce_index in range(max_bounces):
		lookup_shape.radius = chain_jump_radius
		
		# Execute a secondary spatial sweep centered precisely on the current hit target
		var intersections := SpatialQuery.query_shape_intersections(
			space_state,
			lookup_shape,
			active_search_position,
			enemy_collision_mask,
			max_results_buffer
		)
		
		if intersections.is_empty():
			break

		var next_target: HurtboxComponent = null
		var shortest_dist_sq := chain_jump_radius * chain_jump_radius
		
		# Proximity filtering layout logic for cascading chains
		for result in intersections:
			var target_collider = result.get("collider") as Node2D
			if is_instance_valid(target_collider) and target_collider is HurtboxComponent:
				var instance_id := target_collider.get_instance_id()
				
				# Enforce bounce safety rules: Do not hit the same enemy twice during a single cast tree loop
				if excluded_instance_ids.has(instance_id):
					continue
					
				var dist_sq := active_search_position.distance_squared_to(target_collider.global_position)
				if dist_sq < shortest_dist_sq:
					shortest_dist_sq = dist_sq
					next_target = target_collider

		# Apply cascade hit if a valid untargeted neighbor unit exists
		if is_instance_valid(next_target):
			excluded_instance_ids.append(next_target.get_instance_id())
			next_target.take_hit(final_payload)
			active_search_position = next_target.global_position
		else:
			break 

	delivery_finished.emit()
