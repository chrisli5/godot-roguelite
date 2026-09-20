class_name ChainLinkDriver
extends GeometryDriver

@export_group("Physics Hardware Configuration")
@export_flags_2d_physics var enemy_collision_mask: int = 4
@export var max_results_buffer: int = 32

@export_group("Chain Metrics Configuration")
## Base circle radius of the initial impact check zone before player AoE scaling applies
@export var primary_strike_radius: float = 48.0
## The maximum jump range radius between subsequent chaining targets in pixels
@export var chain_jump_radius: float = 120.0
## Total maximum number of bounce branches executed per cast tick (e.g., 4 jumps)
@export var max_bounces: int = 4


## Executes an instantaneous branching query tree pass across physics servers.
func execute_delivery(
	global_origin: Vector2, 
	target_direction: Vector2, 
	current_speed: float, 
	current_aoe_scale: float, 
	final_payload: HitPayload
) -> void:
	
	var space_state := get_viewport().get_world_2d().direct_space_state
	if not space_state:
		delivery_finished.emit()
		return

	# Pre-allocate circle shapes to reduce allocations inside the query loops
	var lookup_shape := CircleShape2D.new()
	
	# Cache tracking array block holding onto instance IDs hit during THIS individual pass
	var excluded_instance_ids: Array[int] = []
	
	# Start tracking position registers from the cast center origin point
	var active_search_position := global_origin
	var current_radius := primary_strike_radius * current_aoe_scale
	
	# --- ITERATIVE BRANCHING SEARCH MATRICES ---
	for bounce_index in range(max_bounces + 1):
		lookup_shape.radius = current_radius
		
		# 1. Execute direct-space shape query
		var intersections := SpatialQuery.query_shape_intersections(
			space_state,
			lookup_shape,
			active_search_position,
			enemy_collision_mask,
			max_results_buffer
		)
		
		if intersections.is_empty():
			break # Chain breaks early if no viable targets sit within radius bounds

		# 2. Parse out the single closest target that has NOT been hit on this pass yet
		var next_target: HurtboxComponent = null
		var shortest_dist_sq := current_radius * current_radius
		
		for result in intersections:
			var target_collider = result.get("collider") as Node2D
			if is_instance_valid(target_collider) and target_collider is HurtboxComponent:
				var instance_id := target_collider.get_instance_id()
				
				# Block double-striking targets inside the active chain execution line
				if excluded_instance_ids.has(instance_id):
					continue
					
				var dist_sq := active_search_position.distance_squared_to(target_collider.global_position)
				if dist_sq < shortest_dist_sq:
					shortest_dist_sq = dist_sq
					next_target = target_collider

		# 3. Handle strike evaluation step
		if is_instance_valid(next_target):
			# Log target to prevent infinite loops
			excluded_instance_ids.append(next_target.get_instance_id())
			
			# Deliver the parent-mediated combat package directly to the target lane
			next_target.take_hit(final_payload)
			
			# Shift coordinates over to branch forward out from this hit enemy position vector next!
			active_search_position = next_target.global_position
			current_radius = chain_jump_radius * current_aoe_scale
		else:
			break # Break sequence if all targets caught within bounds are already dead/excluded

	# --- IMMEDIATE-MODE RESOLUTION HANDOFF ---
	# Alert the parent Ability wrapper that the cascading branch pass completed instantly
	delivery_finished.emit()
