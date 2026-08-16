class_name UpgradeBlueprintProfile
extends Resource

enum ProfileBehavior { SINGLE_CARD_LINE, BUNDLE_LIST }

@export_group("Profile Mode")
@export var behavior_mode: ProfileBehavior = ProfileBehavior.SINGLE_CARD_LINE

@export_group("Single Template Configurations")
@export var definition_template: UpgradeDefinition
@export var total_tiers: int = 5
@export var initial_unlock_level: int = 1
@export var levels_per_tier: int = 2

@export_group("Bundle List Configurations")
@export var definition_bundle: Array[UpgradeDefinition] = []


func generate_trackers() -> Array[UpgradeTracker]:
	if behavior_mode == ProfileBehavior.BUNDLE_LIST:
		return _generate_bundle_trackers()
	return _generate_single_line_trackers()


func _generate_bundle_trackers() -> Array[UpgradeTracker]:
	var generated_list: Array[UpgradeTracker] = []
	for template in definition_bundle:
		if not is_instance_valid(template): continue
			
		var tracker = UpgradeTracker.new()
		tracker.definition = template.duplicate()
			
		# Explicit Assignment Pass
		tracker.required_character_level = initial_unlock_level
		tracker.required_infusion_level = 0 # Standard baseline evolution gate target
		tracker.tier_index = 1
		tracker.max_purchases = 1
		tracker.current_purchases = 0
		generated_list.append(tracker)
		
	return generated_list


func _generate_single_line_trackers() -> Array[UpgradeTracker]:
	var generated_list: Array[UpgradeTracker] = []
	if not is_instance_valid(definition_template): return generated_list
		
	var dynamic_max_tiers = 1 if definition_template.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK else total_tiers
		
	for tier in range(dynamic_max_tiers):
		var current_tier_num = tier + 1
		var tracker = UpgradeTracker.new()
		var unique_definition = definition_template.duplicate(true)
		
		tracker.definition = unique_definition
		# Linear character stat cards increment their level requirement smoothly
		tracker.required_character_level = initial_unlock_level + (tier * levels_per_tier)
		tracker.required_infusion_level = 1 # Linear cards do not care about recipe checks
		tracker.tier_index = current_tier_num
		tracker.max_purchases = 1 
		tracker.current_purchases = 0
		generated_list.append(tracker)
		
	return generated_list
