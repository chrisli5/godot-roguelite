class_name CombatCalculations
extends RefCounted

## Master pipeline function that builds a ready-to-use HitPayload.
## [param caster]: The Entity or Node initiating the strike.
## [param source_stats]: The StatsContainer of the specific weapon or entity.
## [param source_tags]: The TagComponent of the specific weapon or entity.
static func generate_hit_payload(caster: Node2D, source_stats: StatsContainer, source_tags: TagComponent) -> HitPayload:
	var payload = HitPayload.new()
	payload.caster = caster
	
	# 1. Harvest base tags from the source asset if they exist
	if is_instance_valid(source_tags):
		payload.damage_tags = source_tags.get_active_tags()
		
	# 2. Extract baseline attributes out of the stats container track
	if is_instance_valid(source_stats):
		var base_damage: float = source_stats.get_stat_value(Stat.Type.DAMAGE, 10.0)
		var crit_chance: float = source_stats.get_stat_value(Stat.Type.CRIT_CHANCE, 0.05) # 5% baseline
		var crit_mult: float = source_stats.get_stat_value(Stat.Type.CRIT_MULTIPLIER, 1.5)  # 150% baseline
		
		# 3. Execute the Multiplier Calculation Equations
		var is_critical_hit: bool = randf() < crit_chance
		var calculated_damage: float = base_damage
		
		if is_critical_hit:
			calculated_damage *= crit_mult
			# Append a temporary indicator tag so receivers know to play unique visual feedback (e.g. crit text bounce)
			payload.damage_tags.append(Tags.Type.CROWD_CONTROL) 
			
		payload.final_damage = calculated_damage
	else:
		# Safety fallback if hit logic originates from an object without standard stats
		payload.final_damage = 10.0
		
	return payload
