class_name UpgradeTreeComponent
extends Node

@export_group("Database Profiling Templates")
@export var blueprint_profiles: Array[UpgradeBlueprintProfile] = []

@export_group("Runtime Live Trackers")
@export var available_upgrades: Array[UpgradeTracker] = []

var purchased_upgrade_ids: Array[String] = []

func _ready() -> void:
	_compile_procedural_blueprints()

func _compile_procedural_blueprints() -> void:
	for profile in blueprint_profiles:
		if is_instance_valid(profile):
			var trackers = profile.generate_trackers()
			available_upgrades.append_array(trackers)


func get_eligible_upgrades(context_level: int) -> Array[UpgradeTracker]:
	var eligible_trackers: Array[UpgradeTracker] = []
	
	for tracker in available_upgrades:
		if tracker.current_purchases >= tracker.max_purchases:
			continue
		if context_level < tracker.required_level:
			continue
			
		var prerequisites_met = true
		for prereq_id in tracker.prerequisite_upgrade_ids:
			if not purchased_upgrade_ids.has(prereq_id):
				prerequisites_met = false
				break
				
		if prerequisites_met:
			eligible_trackers.append(tracker)
			
	return eligible_trackers


func register_purchase(upgrade_id: String) -> void:
	purchased_upgrade_ids.append(upgrade_id)
