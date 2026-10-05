class_name AreaGeometry
extends GeometryDriver


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
