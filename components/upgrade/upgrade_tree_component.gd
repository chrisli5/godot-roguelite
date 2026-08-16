class_name UpgradeTreeComponent
extends Node

@export_group("Database Profiling Templates")
@export var blueprint_profiles: Array[UpgradeBlueprintProfile] = []

@export_group("Runtime Live Trackers")
@export var available_upgrades: Array[UpgradeTracker] = []

## Direct map tracking current run progression status: {"fire": 5, "player_speed": 2}
var purchase_levels: Dictionary[String, int] = {}

# --- Local Cache Storage Pools ---
var _cached_eligible_upgrades: Array[UpgradeTracker] = []
var _cached_eligible_evolutions: Array[UpgradeTracker] = []


func _ready() -> void:
	_compile_procedural_blueprints()
	# Perform an initial sweep to populate the caches for level 1 character choices
	rebuild_upgrade_caches([], 1)
	

func _compile_procedural_blueprints() -> void:
	for profile in blueprint_profiles:
		if is_instance_valid(profile):
			var trackers = profile.generate_trackers()
			available_upgrades.append_array(trackers)


func get_cached_upgrades() -> Array[UpgradeTracker]:
	return _cached_eligible_upgrades


func get_cached_evolutions() -> Array[UpgradeTracker]:
	return _cached_eligible_evolutions


func get_upgrade_id_from_element(element_tag: Tags.Type) -> String:
	match element_tag:
		Tags.Type.FIRE: return "inf_fire"
		Tags.Type.FROST: return "inf_frost"
		Tags.Type.WIND: return "inf_wind"
		Tags.Type.LIGHTNING: return "inf_lightning"
		_: return ""


func rebuild_upgrade_caches(active_tags: Array[Tags.Type], player_character_level: int) -> void:
	_cached_eligible_upgrades.clear()
	_cached_eligible_evolutions.clear()
	
	for tracker in available_upgrades:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases:
			continue
			
		# --- Fix Rule 1: Always check core Character Level first across all card types ---
		if player_character_level < tracker.required_character_level:
			continue
			
		# --- Process Standard Progression Upgrades ---
		if definition.payload_type == UpgradeDefinition.PayloadType.STAT_MODIFIER:
			var current_acquired_tier = purchase_levels.get(definition.upgrade_id, 0)
			if tracker.tier_index == current_acquired_tier + 1:
				_cached_eligible_upgrades.append(tracker)
				
		# --- Process Evolution Ability Unlocks ---
		elif definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			# 1. Elemental Recipe Tag Check
			var recipe_satisfied = true
			for required_tag in definition.tags:
				if not active_tags.has(required_tag):
					recipe_satisfied = false
					break
			if not recipe_satisfied:
				continue

			# --- Fix Rule 2: Check Infusion depth explicitly against the target property ---
			var targeted_infusion_gate: int = tracker.required_infusion_level
			var all_infusions_meet_requirement: bool = true
			
			for req_tag in definition.tags:
				if req_tag == Tags.Type.INFUSION: continue
					
				var target_upgrade_key = get_upgrade_id_from_element(req_tag)
				var current_infusion_level = purchase_levels.get(target_upgrade_key, 0)
				
				if current_infusion_level < targeted_infusion_gate:
					all_infusions_meet_requirement = false
					break 
			
			if all_infusions_meet_requirement:
				_cached_eligible_evolutions.append(tracker)


func register_purchase(base_upgrade_id: String, active_tags: Array[Tags.Type], player_character_level: int) -> void:
	if purchase_levels.has(base_upgrade_id):
		purchase_levels[base_upgrade_id] += 1
	else:
		purchase_levels[base_upgrade_id] = 1
		
	rebuild_upgrade_caches(active_tags, player_character_level)
