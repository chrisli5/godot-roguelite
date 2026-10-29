class_name StateInspector
extends RefCounted
## Debug only. Describes what the game currently believes about the player, each ability slot and the nearest enemy,
## as plain data (describe) and as deterministic text (to_text). Read-only: nothing here clears a dirty flag, recomputes a
## stat, adds a modifier or emits a stat signal. It reads Stat fields directly and uses only pure ledger queries.

const MISMATCH := "MISMATCH"


## Plain data for the Inspect tab: {"player": {...}, "slots": [...], "enemy": {...}}. Keeps no node or resource references.
## `hits` is the DebugHitRecorder's per-slot dictionary; an entry may carry "age_s" (seconds since the hit), added by the caller.
static func describe(player: Player, nearest_enemy: Enemy, hits: Dictionary) -> Dictionary:
	var description := {"player": {}, "slots": [], "enemy": {}}
	if not is_instance_valid(player):
		return description

	var ledger := player.run_ledger_component
	var no_tags: Array[Tags.Type] = []
	description["player"] = {
		"stats": _stat_rows(player.stats_container, ledger, 0, no_tags),
		"statuses": _status_lines(player.status_effect_component),
	}

	var slots: Array = []
	for slot in range(AbilityContainer.MIN_SLOT, AbilityContainer.MAX_SLOT + 1):
		slots.append(_describe_slot(player, slot, hits))
	description["slots"] = slots

	if is_instance_valid(nearest_enemy):
		description["enemy"] = {
			"name": String(nearest_enemy.name),
			"statuses": _status_lines(nearest_enemy.status_effect_component),
		}
	return description


## Deterministic text for a describe() result: the same input always gives the same string.
static func to_text(description: Dictionary) -> String:
	var lines: Array[String] = []
	var player: Dictionary = description.get("player", {})
	if player.is_empty():
		return "no player"

	lines.append("== Player core (slot 0) ==")
	_append_stat_rows(lines, player["stats"])
	_append_statuses(lines, "Player statuses", player["statuses"])

	for slot_data in description.get("slots", []):
		lines.append("")
		if slot_data.get("empty", false):
			lines.append("Slot %d: empty" % slot_data["slot"])
			continue
		lines.append("== Slot %d: %s ==" % [slot_data["slot"], slot_data["name"]])
		lines.append("Evolution state: %s | Overclocked: %s | Offer eligible: %s" % [slot_data["evolution_state"], slot_data["overclocked"], slot_data["offer_eligible"]])
		lines.append("Infusion levels: %s" % _join_or_none(slot_data["infusion_levels"]))
		lines.append("Permanent tags: %s" % _join_or_none(slot_data["permanent_tags"]))
		lines.append("Active tags: %s" % _join_or_none(slot_data["active_tags"]))
		var card_texts: Array = []
		for card in slot_data["cards"]:
			card_texts.append("%s x%d (%s)" % [card["name"], card["tier"], card["category"]])
		lines.append("Cards applying: %s" % _join_or_none(card_texts))
		lines.append("Statuses resolved: %s" % _join_or_none(slot_data["statuses"]))
		lines.append("Impact bursts resolved: %s" % _join_or_none(slot_data["bursts"]))
		_append_stat_rows(lines, slot_data["stats"])
		lines.append("Last hit: %s" % _hit_text(slot_data["last_hit"]))

	lines.append("")
	var enemy: Dictionary = description.get("enemy", {})
	if enemy.is_empty():
		lines.append("Nearest enemy: no enemy")
	else:
		lines.append("Nearest enemy: %s" % enemy["name"])
		_append_statuses(lines, "Enemy statuses", enemy["statuses"])
	return "\n".join(lines)


## "dirty" when the cached value is stale by design, "ok" when the clean cache matches `expected`, "MISMATCH" when it is
## clean but wrong (a purchase or tag change that failed to invalidate a cache), "n/a" for a container without a ledger.
static func cache_state_of(stat: Stat, expected: float, has_ledger: bool) -> String:
	if not has_ledger:
		return "n/a"
	if stat.is_dirty:
		return "dirty"
	var tolerance := maxf(0.0001, 0.0001 * absf(expected))
	if absf(stat.current_value - expected) <= tolerance:
		return "ok"
	return MISMATCH


## The value a clean cache should hold, recomputed without touching the stat.
## NOTE: this mirrors StatsContainer._calculate_stat and Stat.recalculate_runtime_value and must be replaced by the shared
## function when the planned "single stat formula" refactor lands. It checks cache freshness; it is not an independent
## proof that the formula is right.
static func expected_value(stat: Stat, totals: Vector3) -> float:
	var baseline := (stat.base_value + totals.x) * (1.0 + totals.y) * totals.z
	var flat_total := baseline
	var percent_total := 0.0
	var multiplicative_total := 1.0
	for modifier in stat.transient_modifiers:
		if modifier.type == StatModifier.Type.FLAT:
			flat_total += modifier.value
		elif modifier.type == StatModifier.Type.PERCENT:
			percent_total += modifier.value
		elif modifier.type == StatModifier.Type.MULTIPLICATIVE:
			multiplicative_total *= 1.0 + modifier.value
	return clampf(flat_total * (1.0 + percent_total) * multiplicative_total, 0.0, 9999.0)


# ---------------------------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------------------------

static func _describe_slot(player: Player, slot: int, hits: Dictionary) -> Dictionary:
	var ability: Ability = player.ability_container.get_ability_by_slot(slot)
	if not is_instance_valid(ability):
		return {"slot": slot, "empty": true}

	var ledger := player.run_ledger_component
	var permanent_tags := ability.tag_component.get_permanent_tags()
	var levels := ledger.get_infusion_levels(slot)

	var cards: Array = []
	for definition in ledger.active_upgrades:
		var tier := ledger.get_card_tier(definition, slot, permanent_tags)
		if tier > 0:
			cards.append({"name": definition.display_name, "tier": tier, "category": UpgradeDefinition.Category.keys()[definition.category]})

	var status_ids: Array = []
	for effect in ledger.get_status_effects(slot, permanent_tags):
		status_ids.append(effect.effect_id)
	var burst_ids: Array = []
	for burst in ledger.get_impact_bursts(slot, permanent_tags):
		burst_ids.append(String(burst.burst_id))

	var gate := ability.evolution_gate_component
	return {
		"slot": slot,
		"empty": false,
		"name": ability.display_name,
		"evolution_state": EvolutionGateComponent.EvolutionState.keys()[gate.current_state],
		"overclocked": gate.is_permanently_overclocked,
		"offer_eligible": gate.is_offer_eligible(levels),
		"infusion_levels": _infusion_level_texts(levels),
		"permanent_tags": _tag_names(permanent_tags),
		"active_tags": _tag_names(ability.tag_component.get_active_tags()),
		"cards": cards,
		"statuses": status_ids,
		"bursts": burst_ids,
		"stats": _stat_rows(ability.stats_container, ledger, slot, permanent_tags),
		"last_hit": (hits[slot] as Dictionary).duplicate(true) if hits.has(slot) else {},
	}


static func _stat_rows(container: StatsContainer, ledger: RunLedgerComponent, slot: int, tags: Array[Tags.Type]) -> Array:
	var rows: Array = []
	var has_ledger := is_instance_valid(ledger)
	var stat_types := container.stats.keys()
	stat_types.sort()
	for stat_type in stat_types:
		var stat: Stat = container.stats[stat_type]
		var totals := Vector3(0.0, 0.0, 1.0)
		if has_ledger:
			totals = ledger.get_modifier_totals(slot, tags, stat_type)
		var expected := expected_value(stat, totals)
		rows.append({
			"name": String(Stat.Type.keys()[stat_type]),
			"base": stat.base_value,
			"flat": totals.x,
			"percent": totals.y,
			"multiplicative": totals.z,
			"cached": stat.current_value,
			"transient_count": stat.transient_modifiers.size(),
			"expected": expected,
			"cache_state": cache_state_of(stat, expected, has_ledger),
		})
	return rows


static func _status_lines(component: StatusEffectComponent) -> Array:
	var lines: Array = []
	if not is_instance_valid(component):
		return lines
	for instance in component.get_active_instances():
		lines.append({
			"effect_id": instance.template.effect_id,
			"time_remaining": instance.time_remaining,
			"ramp": instance.get_ramp_multiplier(),
			"dot_damage": instance.dot_damage,
			"duration_bonus": instance.duration_bonus,
			"ramp_cap_bonus": instance.ramp_cap_bonus,
			"magnitude_bonus": instance.magnitude_bonus,
			"has_buildup": instance.template.buildup_per_application > 0.0,
			"buildup": instance.buildup,
			"is_frozen": instance.is_frozen,
			"immunity_time_left": instance.immunity_time_left,
		})
	return lines


static func _tag_names(tags: Array[Tags.Type]) -> Array:
	var names: Array = []
	for tag in tags:
		names.append(String(Tags.Type.keys()[tag]))
	return names


## "FIRE 3" style entries for the nonzero levels, in the order Tags.get_index_from_element uses.
static func _infusion_level_texts(levels: Array[int]) -> Array:
	var element_names: Array[String] = ["", "", "", "", ""]
	for tag_value in Tags.Type.values():
		var index := Tags.get_index_from_element(tag_value)
		if index >= 0 and index < element_names.size():
			element_names[index] = String(Tags.Type.keys()[tag_value])
	var texts: Array = []
	for index in range(levels.size()):
		if levels[index] > 0:
			texts.append("%s %d" % [element_names[index], levels[index]])
	return texts


# ---------------------------------------------------------------------------------------------
# Text
# ---------------------------------------------------------------------------------------------

static func _append_stat_rows(lines: Array[String], rows: Array) -> void:
	for row in rows:
		lines.append("  %s: base %.2f | flat %.2f percent %.2f mult %.2f | cached %.2f | transient %d | %s" % [
			row["name"], row["base"], row["flat"], row["percent"], row["multiplicative"], row["cached"], row["transient_count"],
			row["cache_state"],
		])


static func _append_statuses(lines: Array[String], title: String, statuses: Array) -> void:
	if statuses.is_empty():
		lines.append("%s: none" % title)
		return
	lines.append("%s:" % title)
	for status in statuses:
		lines.append("  %s: %.2f s left, ramp x%.2f, dot %.2f, duration bonus %.2f, ramp cap bonus %.2f, magnitude bonus %.2f" % [
			status["effect_id"], status["time_remaining"], status["ramp"], status["dot_damage"],
			status["duration_bonus"], status["ramp_cap_bonus"], status["magnitude_bonus"],
		])
		if status.get("has_buildup", false):
			lines[lines.size() - 1] += ", meter %.2f, frozen %s, immunity %.2f s" % [
				status["buildup"], "yes" if status["is_frozen"] else "no", status["immunity_time_left"],
			]


static func _join_or_none(items: Array) -> String:
	if items.is_empty():
		return "none"
	var texts: Array[String] = []
	for item in items:
		texts.append(str(item))
	return ", ".join(texts)


static func _hit_text(hit: Dictionary) -> String:
	if hit.is_empty():
		return "no hit recorded"
	var text := "%s damage %.2f%s%s, tags [%s], statuses [%s], bursts [%s], dot %.2f, duration %.2f, ramp cap %.2f, magnitude %.2f" % [
		hit["enemy_name"], hit["final_damage"],
		" (crit)" if hit["is_critical_hit"] else "",
		" (burst)" if hit["is_burst"] else "",
		", ".join(hit["damage_tags"]), ", ".join(hit["status_ids"]), ", ".join(hit["burst_ids"]),
		hit["dot_damage_snapshot"], hit["status_duration_snapshot"], hit["status_ramp_cap_snapshot"],
		hit["status_magnitude_snapshot"],
	]
	if hit.has("age_s"):
		text += " (%.1f s ago)" % hit["age_s"]
	return text
