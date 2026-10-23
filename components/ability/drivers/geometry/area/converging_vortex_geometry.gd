# res://components/ability/drivers/geometry/converging_vortex_geometry.gd
class_name ConvergingVortexGeometry
extends AreaGeometry # Inherits the clean uniform AoE loop helper

@export var horizontal_suction_force: float = 450.0

## The script only implements the exact calculation where its behavior diverges!
func _process_volume_hit(hurtbox: HurtboxComponent, origin: Vector2, payload: CombatPayload) -> void:
	var stats := _stats_of(payload)
	var max_radius = StatBonus.reach(stats, Stat.Type.AOE_RADIUS) if is_instance_valid(stats) else 160.0

	var entity = hurtbox.owner_entity as CharacterBody2D
	if is_instance_valid(entity):
		var pull_vector: Vector2 = origin - entity.global_position
		var distance := pull_vector.length()
		
		if distance > 8.0:
			var pull_direction := pull_vector.normalized()
			var falloff_weight: float = 1.0 - (distance / max_radius)
			var calculated_force := horizontal_suction_force * (1.0 + falloff_weight)
				
			entity.velocity += pull_direction * calculated_force
