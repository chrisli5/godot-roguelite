class_name StatsContainer
extends Node

signal stat_updated(stat_type: Stat.Type, new_value: float)

var profile: StatsProfile
var stats: Dictionary[Stat.Type, Stat] = {}


func initialize_profile(stats_profile: StatsProfile) -> void:
	profile = stats_profile
	if not profile:
		push_warning("StatsContainer on %s missing a StatsProfile!" % get_parent().name)
		return
		
	for stat in profile.default_stats:
		if not stat:
			continue
			
		var duplicated_stat: Stat = stat.duplicate(true) as Stat
		stats[duplicated_stat.type] = duplicated_stat
		
		duplicated_stat.value_changed.connect(_on_stat_value_changed.bind(duplicated_stat))
		duplicated_stat.update_value()


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
