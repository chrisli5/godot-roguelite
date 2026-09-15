class_name UpgradeLedgerComponent
extends Node

@export_group("Blueprint Profiles")
@export var stat_blueprint_profiles: Array[UpgradeBlueprintProfile] = []
@export var infusion_blueprint_profiles: Array[UpgradeBlueprintProfile] = []
@export var evo_blueprint_profiles: Array[UpgradeBlueprintProfile] = []
@export var overclock_blueprint_profile: UpgradeBlueprintProfile

var available_upgrades: Array[UpgradeTracker] = []
var available_infusions: Array[UpgradeTracker] = []
var available_evolutions: Array[UpgradeTracker] = []
var overclock_tracker: UpgradeTracker = null

# Centralized ledger purchase log framework
var purchase_levels: Dictionary[String, int] = {}

# Pre-compiled local O(1) cache pools served straight to the UI
var _cached_eligible_upgrades: Array[UpgradeTracker] = []
var _cached_eligible_evolutions: Array[UpgradeTracker] = []


func _ready() -> void:
	for profile in stat_blueprint_profiles:
		if is_instance_valid(profile):
			available_upgrades.append_array(profile.generate_trackers())
			
	for profile in evo_blueprint_profiles:
		if is_instance_valid(profile):
			available_evolutions.append_array(profile.generate_trackers())
	
	for profile in infusion_blueprint_profiles:
		if is_instance_valid(profile):
			available_infusions.append_array(profile.generate_trackers())

	if is_instance_valid(overclock_blueprint_profile):
			var generated = overclock_blueprint_profile.generate_trackers()
			if not generated.is_empty():
				overclock_tracker = generated[0]


func get_cached_upgrades() -> Array[UpgradeTracker]: return _cached_eligible_upgrades
func get_cached_evolutions() -> Array[UpgradeTracker]: return _cached_eligible_evolutions


func log_purchase_entry(base_upgrade_id: String) -> void:
	if purchase_levels.has(base_upgrade_id):
		purchase_levels[base_upgrade_id] += 1
	else:
		purchase_levels[base_upgrade_id] = 1


func clear_caches() -> void:
	_cached_eligible_upgrades.clear()
	_cached_eligible_evolutions.clear()


func overwrite_cached_pools(upgrades: Array[UpgradeTracker], evolutions: Array[UpgradeTracker]) -> void:
	_cached_eligible_upgrades = upgrades
	_cached_eligible_evolutions = evolutions
