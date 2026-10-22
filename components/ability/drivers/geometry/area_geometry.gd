class_name AreaGeometry
extends GeometryDriver


## Area reach comes from AOE_RADIUS; the QUERY_RADIUS circle is only the fallback.
func get_query_shape(stats: StatsContainer) -> Shape2D:
	var circle := CircleShape2D.new()
	var fallback: float = stats.get_final_stat_value(Stat.Type.QUERY_RADIUS) if is_instance_valid(stats) else 200.0
	circle.radius = _get_area_radius(stats, fallback)
	return circle


## Geometry contract: the family of this geometry.
func get_family() -> StringName:
	return &"area_instant"


## Geometry contract: the stats that set how far this geometry reaches.
func get_reach_stats() -> Array[Stat.Type]:
	return [Stat.Type.AOE_RADIUS]


## Geometry contract: the stats that set how fast this geometry moves or advances.
func get_speed_stats() -> Array[Stat.Type]:
	return []


func _process_volume_hit(_hurtbox: HurtboxComponent, _origin: Vector2, _payload: CombatPayload) -> void:
	pass


func execute_geometry(query_results: Dictionary, final_payload: CombatPayload) -> void:
	if not is_instance_valid(final_payload):
		delivery_finished.emit()
		return
		
	var hit_nodes: Array = query_results.get("hit_nodes", [])
	var origin: Vector2 = query_results.get("origin", Vector2.ZERO)

	if hit_nodes.is_empty():
		delivery_finished.emit()
		return

	# Standardized distribution loop runs completely automatically for all children
	for hurtbox in hit_nodes:
		if is_instance_valid(hurtbox) and hurtbox is HurtboxComponent:
			# Apply damage cleanly across the uniform contract
			hurtbox.take_hit(final_payload)
			
			# Invoke polymorphic child behavior overrides seamlessly on the same frame pass
			_process_volume_hit(hurtbox, origin, final_payload)

	delivery_finished.emit()
