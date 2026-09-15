class_name StatsContainer
extends Node

signal stat_updated(stat_type: Stat.Type, new_value: float)

var stats: Dictionary[Stat.Type, Stat] = {}


func initialize_profile(profile: StatsProfile) -> void:
	if not profile:
		return
		
	for stat_type in profile.base_stats.keys():
		var runtime_stat = Stat.new()
		runtime_stat.type = stat_type
		runtime_stat.base_value = profile.base_stats[stat_type]
		
		stats[stat_type] = runtime_stat
		runtime_stat.value_changed.connect(_on_stat_value_changed.bind(runtime_stat))
		runtime_stat.update_value()


func mutate_base_profile(new_profile: StatsProfile) -> void:
	if not is_instance_valid(new_profile):
		return
		
	# 1. Harvest and cache all running modifier resources in RAM safely before wiping values
	var preserved_modifiers: Dictionary[Stat.Type, Array] = {}
	for stat_type in stats.keys():
		var runtime_stat: Stat = stats[stat_type]
		if runtime_stat and not runtime_stat.modifiers.is_empty():
			preserved_modifiers[stat_type] = runtime_stat.modifiers.duplicate()
			
	# 2. Sever signal bindings and clear out the old baseline dictionary frame completely
	for stat_type in stats.keys():
		var runtime_stat: Stat = stats[stat_type]
		if runtime_stat and runtime_stat.value_changed.is_connected(_on_stat_value_changed):
			runtime_stat.value_changed.disconnect(_on_stat_value_changed)
	stats.clear()
	
	# 3. Inject the new evolution baseline blueprint layer mapping
	for stat_type in new_profile.base_stats.keys():
		var new_runtime_stat = Stat.new()
		new_runtime_stat.type = stat_type
		new_runtime_stat.base_value = new_profile.base_stats[stat_type]
		
		stats[stat_type] = new_runtime_stat
		new_runtime_stat.value_changed.connect(_on_stat_value_changed.bind(new_runtime_stat))
		
		# 4. Re-stitch the preserved investment cards cleanly back into the new stat frame lane
		if preserved_modifiers.has(stat_type):
			for modifier in preserved_modifiers[stat_type]:
				new_runtime_stat.add_modifier(modifier)
				
		# Force a GPU/RAM calculation pass update right now
		new_runtime_stat.update_value()


func get_stat(stat_type: Stat.Type) -> Stat:
	return stats.get(stat_type, null) as Stat


func get_stat_value(stat_type: Stat.Type, default: float = 0.0) -> float:
	var tracking_stat: Stat = get_stat(stat_type)
	return tracking_stat.current_value if tracking_stat else default


func add_modifier(stat_type: Stat.Type, modifier: StatModifier) -> void:
	var tracking_stat: Stat = get_stat(stat_type)
	if tracking_stat:
		tracking_stat.add_modifier(modifier)
	else:
		push_warning("Cannot add modifier: Stat %s not found!" % Stat.Type.keys()[stat_type])


func remove_modifier(stat_type: Stat.Type, modifier_id: String) -> void:
	var tracking_stat: Stat = get_stat(stat_type)
	if tracking_stat:
		tracking_stat.remove_modifier(modifier_id)


func _on_stat_value_changed(value: float, stat: Stat) -> void:
	stat_updated.emit(stat.type, value)
