class_name StatsContainer
extends Node

signal stat_updated(stat_type: Stat.Type, new_value: float)

var stats: Dictionary[Stat.Type, Stat] = {}
var _slot_owner_index: int = 0
var _cached_tags: Array[Tags.Type] = []


func configure_slot_context(slot_idx: int) -> void:
	_slot_owner_index = slot_idx
	_connect_to_ledger_broadcast()


func _connect_to_ledger_broadcast() -> void:
	var current_player = instance_from_id(EventBus.active_player_instance_id) as Player
	if is_instance_valid(current_player) and is_instance_valid(current_player.run_ledger_component):
		current_player.run_ledger_component.stats_invalidated.connect(_on_stats_invalidated)


## THE LAZY READ GATING ENGINE:
## Performs a true O(1) float read 99.9% of the time. 
## Recalculates ONLY on the single frame pass where the cache was flagged as dirty.
func get_final_stat_value(stat_type: Stat.Type, active_tags: Array[Tags.Type] = []) -> float:
	var tracking_stat := stats.get(stat_type, null) as Stat
	if not tracking_stat:
		return 10.0
		
	# Synchronize active tags cache for compilation passes
	_cached_tags = active_tags
	
	# THE LAZY EVALUATION GATE:
	# If the flag is dirty, we run a single compilation pass right now before returning the total
	if tracking_stat.is_dirty:
		_calculate_stat(stat_type)
		
	return tracking_stat.current_value


## THE BULK INVALIDATION PASS (Used on first-time setups or morphology weapon evolutions)
func invalidate_all_caches() -> void:
	for stat_type in stats.keys():
		stats[stat_type].is_dirty = true


## REFACTORED LIGHTWEIGHT LISTENERS:
## This event now costs almost ZERO performance overhead. It simply toggles boolean flags.
func _on_stats_invalidated(definition: UpgradeDefinition) -> void:
	if not is_instance_valid(definition): 
		return
		
	var is_impacted := false

	match definition.scope:
		UpgradeDefinition.ScopeType.CHARACTER_CORE:
			if _slot_owner_index == 0:
				is_impacted = true
				
		UpgradeDefinition.ScopeType.LOCAL_SLOT:
			if definition.restrict_to_slot == _slot_owner_index:
				is_impacted = true
				
		UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH:
			if _slot_owner_index > 0:
				var parent_weapon = get_parent()
				if is_instance_valid(parent_weapon) and "tag_component" in parent_weapon:
					var tags_container = parent_weapon.tag_component
					if is_instance_valid(tags_container):
						for req_tag in definition.target_tags:
							if tags_container.has_tag(req_tag):
								is_impacted = true
								break

	# LAZY INVALIDATION: Turn the flag to dirty instantly without running any heavy math
	if is_impacted:
		var tracking_stat = stats.get(definition.target_stat_type, null)
		if tracking_stat:
			tracking_stat.is_dirty = true
			# Print verification indicator to track lazy behaviors
			print("[STAT FLAGGED DIRTY] Slot %d marked '%s' as stale." % [
				_slot_owner_index, 
				Stat.Type.keys()[definition.target_stat_type]
			])


## Internal Calculator: Executed strictly on demand when a fresh read arrives
func _calculate_stat(stat_type: Stat.Type) -> void:
	var tracking_stat := stats[stat_type]
	var calculated_baseline := tracking_stat.base_value
	
	var current_player = instance_from_id(EventBus.active_player_instance_id) as Player
	if is_instance_valid(current_player) and is_instance_valid(current_player.run_ledger_component):
		var ledger_modifiers = current_player.run_ledger_component.compile_modifiers_for_weapon(_slot_owner_index, _cached_tags)
		
		var flat_progression := calculated_baseline
		var percent_progression := 0.0
		
		for mod in ledger_modifiers:
			if mod.target_stat_type == stat_type:
				if mod.type == StatModifier.Type.FLAT:
					flat_progression += mod.value
				elif mod.type == StatModifier.Type.PERCENT:
					percent_progression += mod.value
					
		calculated_baseline = flat_progression * (1.0 + percent_progression)

	var final_computed_value = tracking_stat.recalculate_runtime_value(calculated_baseline)
	stat_updated.emit(stat_type, final_computed_value)


# --- REAL-TIME COMBAT INTERFACES (Toggles flags to force fresh evaluations upon status ticks) ---

func add_modifier(stat_type: Stat.Type, modifier: StatModifier) -> void:
	var tracking_stat := stats.get(stat_type, null) as Stat
	if tracking_stat:
		tracking_stat.add_transient_modifier(modifier)
		stat_updated.emit(stat_type, get_final_stat_value(stat_type, _cached_tags))


func remove_modifier(stat_type: Stat.Type, modifier_id: String) -> void:
	var tracking_stat := stats.get(stat_type, null) as Stat
	if tracking_stat:
		tracking_stat.remove_transient_modifier(modifier_id)
		stat_updated.emit(stat_type, get_final_stat_value(stat_type, _cached_tags))


func initialize_profile(profile: StatsProfile) -> void:
	if not profile: return
	for stat_type in profile.base_stats.keys():
		var runtime_stat = Stat.new()
		runtime_stat.type = stat_type
		runtime_stat.base_value = profile.base_stats[stat_type]
		stats[stat_type] = runtime_stat
	invalidate_all_caches()


func mutate_base_profile(new_profile: StatsProfile) -> void:
	if not is_instance_valid(new_profile): return
	var preserved_transients: Dictionary[Stat.Type, Array] = {}
	for stat_type in stats.keys():
		var runtime_stat: Stat = stats[stat_type]
		if runtime_stat and not runtime_stat.transient_modifiers.is_empty():
			preserved_transients[stat_type] = runtime_stat.transient_modifiers.duplicate()
			
	stats.clear()
	
	for stat_type in new_profile.base_stats.keys():
		var new_runtime_stat = Stat.new()
		new_runtime_stat.type = stat_type
		new_runtime_stat.base_value = new_profile.base_stats[stat_type]
		stats[stat_type] = new_runtime_stat
		
		if preserved_transients.has(stat_type):
			for modifier in preserved_transients[stat_type]:
				new_runtime_stat.add_transient_modifier(modifier)
				
	invalidate_all_caches()
