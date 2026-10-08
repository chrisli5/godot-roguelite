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
## Performs a true O(1) float read 99.9% of the time out of primitive RAM.
## Recalculates ONLY on the frame pass where the cache was flagged as dirty.
func get_final_stat_value(stat_type: Stat.Type, active_tags: Array[Tags.Type] = []) -> float:
	var tracking_stat := stats.get(stat_type, null) as Stat
	if not tracking_stat:
		return 0.0
		
	_cached_tags = active_tags
	
	if tracking_stat.is_dirty:
		_calculate_stat(stat_type)
		
	return tracking_stat.current_value


## THE BULK INVALIDATION PASS (Used on first-time setups or morphology weapon evolutions)
func invalidate_all_caches() -> void:
	for stat_type in stats.keys():
		stats[stat_type].is_dirty = true


## REACTIVELY TOGGLES FLAGS INSTANTLY WITHOUT RUNNING HEAVY BACKGROUND MATH
func _on_stats_invalidated(definition: UpgradeDefinition) -> void:
	if not is_instance_valid(definition) or not is_instance_valid(definition.stat_modifier_payload): 
		return
		
	var target_stat := definition.stat_modifier_payload.target_stat_type
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

	if is_impacted:
		var tracking_stat = stats.get(target_stat, null)
		if tracking_stat:
			tracking_stat.is_dirty = true
			print("[STAT FLAGGED DIRTY] Slot %d marked '%s' as stale." % [
				_slot_owner_index, 
				Stat.Type.keys()[target_stat]
			])


## Internal Calculator: Executed strictly on demand when a fresh read arrives or transients mutate
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
	
	# THE CENTRALIZED SIGNAL EMISSION PASS:
	# Fired uniformly right here whenever numbers are recalculated from the ground up!
	stat_updated.emit(stat_type, final_computed_value)


# --- REAL-TIME COMBAT INTERFACES (Autonomous, single-argument API signatures) ---

func add_modifier(modifier: StatModifier) -> void:
	if not is_instance_valid(modifier): 
		return
		
	var tracking_stat := stats.get(modifier.target_stat_type, null) as Stat
	if tracking_stat:
		tracking_stat.add_transient_modifier(modifier)
		# Instantly forces a calculation run to process the freeze debuff/buff and trigger updates
		_calculate_stat(modifier.target_stat_type)


func remove_modifier(modifier: StatModifier) -> void:
	if not is_instance_valid(modifier): 
		return
		
	var tracking_stat := stats.get(modifier.target_stat_type, null) as Stat
	if tracking_stat:
		tracking_stat.remove_transient_modifier(modifier.id)
		# Instantly forces a calculation run upon status expiration and trigger updates
		_calculate_stat(modifier.target_stat_type)


func initialize_profile(profile: StatsProfile) -> void:
	if not profile: 
		return
		
	for stat_type in profile.base_stats.keys():
		var runtime_stat = Stat.new()
		runtime_stat.type = stat_type
		runtime_stat.base_value = profile.base_stats[stat_type]
		stats[stat_type] = runtime_stat
	
	# 1. Flag everything as dirty to establish the lazy-eval state
	invalidate_all_caches()
	
	# 2. THE CRITICAL INITIALIZATION FIX:
	# Force an immediate calculation pass across all registered baseline types right now!
	# This guarantees that things like starting health and velocity limits build their initial values out of 0.0.
	for stat_type in stats.keys():
		get_final_stat_value(stat_type)


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
