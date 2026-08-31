class_name InfusionTrackerComponent
extends Node

## Audits elemental limits, socket thresholds, and specialty milestones.
## Pure module: Zero references to ledger or gate sibling nodes.

const INFUSION_SOFT_CAP_T1: int = 3
const INFUSION_SOFT_CAP_T2: int = 5
const INFUSION_HARD_CAP: int = 15

#var specialty_cards_purchased: int = 0
var last_calculated_total_infusions: int = 0


func calculate_total_infusions(purchase_levels: Dictionary[String, int]) -> int:
	var total_count: int = 0
	for key in purchase_levels.keys():
		if key.begins_with("inf_"):
			total_count += purchase_levels[key]
	last_calculated_total_infusions = total_count
	return total_count


#func is_specialty_card_allowed() -> bool:
	#var earned_tokens = clampi(last_calculated_total_infusions / 3, 0, 3)
	#return specialty_cards_purchased < earned_tokens


func is_infusion_card_allowed(
	definition: UpgradeDefinition, 
	state: int, 
	is_overclocked: bool, 
	purchase_levels: Dictionary[String, int]
) -> bool:
	if not definition.tags.has(Tags.Type.INFUSION): 
		return true 
		
	var current_level: int = purchase_levels.get(definition.upgrade_id, 0)
	if is_overclocked: 
		return current_level < INFUSION_HARD_CAP

	var active_socket_count: int = 0
	for key in purchase_levels.keys():
		if key.begins_with("inf_") and purchase_levels[key] > 0:
			active_socket_count += 1
			
	match state:
		0: # TIER_1_BASE
			if current_level >= INFUSION_SOFT_CAP_T1 or (current_level == 0 and active_socket_count >= 2): return false
		1: # TIER_2_EVOLVED
			if current_level >= INFUSION_SOFT_CAP_T2 or (current_level == 0 and active_socket_count >= 3): return false
		2: # TIER_3_APEX:
			return current_level < INFUSION_HARD_CAP
			
	return true
