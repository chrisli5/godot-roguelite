class_name RadialPulseGeometry
extends GeometryDriver

@export_group("Physics Hardware Configuration")
@export_flags_2d_physics var enemy_collision_mask: int = 4
@export var max_results_buffer: int = 64


func execute_geometry(query_results: Dictionary, final_payload: CombatPayload) -> void:
	if not is_instance_valid(final_payload):
		delivery_finished.emit()
		return
		
	var hit_nodes: Array = query_results.get("hit_nodes", [])
	if hit_nodes.is_empty():
		delivery_finished.emit()
		return

	for hurtbox in hit_nodes:
		if is_instance_valid(hurtbox) and hurtbox is HurtboxComponent:
			hurtbox.take_hit(final_payload)

	delivery_finished.emit()
