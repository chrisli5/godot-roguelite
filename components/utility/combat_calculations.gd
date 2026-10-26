class_name CombatCalculations
extends Resource

## effect_ids already warned about, so the warning fires once per game run.
static var _warned_effect_ids: Dictionary[String, bool] = {}


## Last cast id handed out; 0 is reserved for "no cast".
static var _last_cast_id: int = 0


static func generate_hit_payload(caster: Node2D, stats: StatsContainer, source_tags: TagComponent) -> CombatPayload:
	var payload = CombatPayload.new()
	_last_cast_id += 1
	payload.cast_id = _last_cast_id
	payload.cast_budget = CastBudget.new()
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
		# Indirect scale (Frost, Wind): applied once per cast, to the hit before the crit roll and to the DoT snapshot.
		var damage_scale: float = stats.get_indirect_damage_scale()
		payload.damage_scale = damage_scale
		var calculated_damage: float = base_damage * damage_scale

		if is_critical_hit:
			calculated_damage *= crit_mult
			# Append a temporary indicator tag so receivers know to play unique visual feedback (e.g. crit text bounce)
			#payload.damage_tags.append(Tags.Type.CROWD_CONTROL) 
			
		payload.final_damage = calculated_damage
		payload.is_critical_hit = is_critical_hit

		# DoT magnitudes are snapshotted here, independent of BASE_DAMAGE and crit.
		payload.dot_damage_snapshot = stats.get_final_stat_value(Stat.Type.DOT_DAMAGE) * damage_scale
		payload.status_duration_snapshot = stats.get_final_stat_value(Stat.Type.STATUS_DURATION)
		payload.status_ramp_cap_snapshot = stats.get_final_stat_value(Stat.Type.STATUS_RAMP_CAP)

		# Plasma: a crit cast scales the DoT snapshot by the share of the crit bonus. Ticks never crit.
		if is_critical_hit:
			var crit_dot_share: float = stats.get_final_stat_value(Stat.Type.CRIT_DOT_SHARE)
			if crit_dot_share > 0.0:
				payload.dot_damage_snapshot *= 1.0 + (crit_mult - 1.0) * crit_dot_share

		# Statuses from the upgrade cards that apply to this ability. Application is guaranteed.
		for effect in stats.get_status_effects():
			if effect.tick_interval > 0.0 and payload.dot_damage_snapshot <= 0.0:
				_warn_missing_dot_damage(effect.effect_id)
				continue
			payload.status_effects_to_apply.append(effect)

		# Impact bursts from the upgrade cards that apply to this ability (fired on hit by the hurtbox).
		for burst in stats.get_impact_bursts():
			payload.impact_bursts.append(burst)
	else:
		# Safety fallback if hit logic originates from an object without standard stats
		payload.final_damage = 10.0

	return payload


static func _warn_missing_dot_damage(effect_id: String) -> void:
	if _warned_effect_ids.has(effect_id):
		return
	_warned_effect_ids[effect_id] = true
	push_warning("Status '%s' skipped: its ability has no DOT_DAMAGE (stat missing from its profile or 0)." % effect_id)
