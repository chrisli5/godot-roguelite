class_name CombatCalculations
extends Resource

## effect_ids already warned about, so the warning fires once per game run.
static var _warned_effect_ids: Dictionary[String, bool] = {}


static func generate_hit_payload(caster: Node2D, stats: StatsContainer, source_tags: TagComponent) -> CombatPayload:
	var payload = CombatPayload.new()
	if is_instance_valid(caster):
		payload.caster_instance_id = caster.get_instance_id()
	
	if is_instance_valid(stats):
		payload.stats_container_id = stats.get_instance_id()
	
	if is_instance_valid(source_tags):
		# Copy: the payload outlives this cast and may be mutated by payload drivers.
		payload.damage_tags = source_tags.get_active_tags().duplicate()
		
	if is_instance_valid(stats):
		var base_damage: float = stats.get_final_stat_value(Stat.Type.BASE_DAMAGE)
		var crit_chance: float = stats.get_final_stat_value(Stat.Type.CRIT_CHANCE) # 5% baseline
		var crit_mult: float = stats.get_final_stat_value(Stat.Type.CRIT_MULTIPLIER)  # 150% baseline
		var is_critical_hit: bool = randf() < crit_chance
		var calculated_damage: float = base_damage
		
		if is_critical_hit:
			calculated_damage *= crit_mult
			# Append a temporary indicator tag so receivers know to play unique visual feedback (e.g. crit text bounce)
			#payload.damage_tags.append(Tags.Type.CROWD_CONTROL) 
			
		payload.final_damage = calculated_damage

		# DoT magnitudes are snapshotted here, independent of BASE_DAMAGE and crit.
		payload.dot_damage_snapshot = stats.get_final_stat_value(Stat.Type.DOT_DAMAGE)
		payload.status_duration_snapshot = stats.get_final_stat_value(Stat.Type.STATUS_DURATION)
		payload.status_ramp_cap_snapshot = stats.get_final_stat_value(Stat.Type.STATUS_RAMP_CAP)

		# Statuses from the upgrade cards that apply to this ability. Application is guaranteed.
		for effect in stats.get_status_effects():
			if effect.tick_interval > 0.0 and payload.dot_damage_snapshot <= 0.0:
				_warn_missing_dot_damage(effect.effect_id)
				continue
			payload.status_effects_to_apply.append(effect)
	else:
		# Safety fallback if hit logic originates from an object without standard stats
		payload.final_damage = 10.0

	return payload


static func _warn_missing_dot_damage(effect_id: String) -> void:
	if _warned_effect_ids.has(effect_id):
		return
	_warned_effect_ids[effect_id] = true
	push_warning("Status '%s' skipped: its ability has no DOT_DAMAGE (stat missing from its profile or 0)." % effect_id)
