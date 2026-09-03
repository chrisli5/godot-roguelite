class_name StatsContainer
extends Node

signal stat_updated(stat_type: Stat.Type, new_value: float)

@export var stats_profile: StatsProfile

var stats: Dictionary[Stat.Type, Stat] = {}

func _ready() -> void:
	if is_instance_valid(stats_profile):
		initialize_profile(stats_profile)
	else:
		push_warning("StatsContainer on '%s' was instantiated without a StatsProfile asset template." % get_parent().name)


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
