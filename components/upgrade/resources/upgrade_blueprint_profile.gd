# res://components/upgrade_system/resources/upgrade_blueprint_profile.gd
class_name UpgradeBlueprintProfile
extends Resource

enum ProfileBehavior { SINGLE_CARD_LINE, BUNDLE_LIST }

@export_group("Profile Mode")
## SINGLE_CARD_LINE: Uses definition_template (great for multi-tier stats).
## BUNDLE_LIST: Uses definition_bundle (great for grouping 1-tier ability unlocks).
@export var behavior_mode: ProfileBehavior = ProfileBehavior.SINGLE_CARD_LINE

@export_group("Single Template Configurations")
@export var definition_template: UpgradeDefinition
@export var total_tiers: int = 5
@export var initial_unlock_level: int = 1
@export var levels_per_tier: int = 2

@export_group("Bundle List Configurations")
## Drop as many distinct 1-tier UpgradeDefinitions (like ability unlocks) here as you want!
@export var definition_bundle: Array[UpgradeDefinition] = []

## Master compilation entry point called by the UpgradeTreeComponent at game start
func generate_trackers() -> Array[UpgradeTracker]:
	if behavior_mode == ProfileBehavior.BUNDLE_LIST:
		return _generate_bundle_trackers()
	return _generate_single_line_trackers()

## Handles the creation of multiple distinct 1-tier cards from an array list
func _generate_bundle_trackers() -> Array[UpgradeTracker]:
	var generated_list: Array[UpgradeTracker] = []
	
	for template in definition_bundle:
		if not is_instance_valid(template): 
			continue
			
		var tracker = UpgradeTracker.new()
		var unique_definition = template.duplicate()
		
		# Ensure unique ID tracking tags exist
		var tier_suffix = "_tier_1"
		if not unique_definition.upgrade_id.ends_with(tier_suffix):
			unique_definition.upgrade_id += tier_suffix
			
		# Enforce ability unlock payload behavior rules automatically 
		if unique_definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			unique_definition.ability_scene_to_unlock = template.ability_scene_to_unlock
			
		tracker.definition = unique_definition
		tracker.required_level = initial_unlock_level # Inherits the base profile level setting
		tracker.max_purchases = 1
		tracker.current_purchases = 0
		
		generated_list.append(tracker)
		
	return generated_list

## Handles the traditional multi-tiered progression card sequences
func _generate_single_line_trackers() -> Array[UpgradeTracker]:
	var generated_list: Array[UpgradeTracker] = []
	if not is_instance_valid(definition_template): 
		return generated_list
		
	var dynamic_max_tiers = total_tiers
	if definition_template.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
		dynamic_max_tiers = 1
		
	for tier in range(dynamic_max_tiers):
		var tracker = UpgradeTracker.new()
		var unique_definition = definition_template.duplicate(true)
		var tier_suffix = "_tier_" + str(tier + 1)
		
		unique_definition.upgrade_id = definition_template.upgrade_id + tier_suffix
		unique_definition.display_name = definition_template.display_name
		
		if dynamic_max_tiers > 1:
			unique_definition.display_name += " " + _get_roman_numeral(tier + 1)
			
		if unique_definition.payload_type == UpgradeDefinition.PayloadType.STAT_MODIFIER:
			if is_instance_valid(unique_definition.modifier):
				unique_definition.modifier.id += tier_suffix
				var tier_multiplier = 1.0 + (tier * 0.5) 
				unique_definition.modifier.value *= tier_multiplier
			
		tracker.definition = unique_definition
		tracker.required_level = initial_unlock_level + (tier * levels_per_tier)
		tracker.max_purchases = 1 
		tracker.current_purchases = 0
		
		#if tier > 0:
			#var previous_tier_id = definition_template.upgrade_id + "_tier_" + str(tier)
			#tracker.prerequisite_upgrade_ids.append(previous_tier_id)
			
		generated_list.append(tracker)
		
	return generated_list

func _get_roman_numeral(number: int) -> String:
	var numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	if number <= numerals.size():
		return numerals[number - 1]
	return str(number)
