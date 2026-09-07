class_name InfusionTrackerComponent
extends Node

## Audits elemental limits, socket thresholds, and specialty milestones.
## Pure module: Zero direct references to ledger or gate sibling nodes.

const INFUSION_SOFT_CAP_T1: int = 3
const INFUSION_SOFT_CAP_T2: int = 5
const INFUSION_HARD_CAP: int = 15

var specialty_cards_purchased: int = 0
var last_calculated_total_infusions: int = 0


## Sweeps across the tracking dictionary logs to count cumulative elemental sockets.
func calculate_total_infusions(purchase_levels: Dictionary[String, int]) -> int:
	var total_count: int = 0
	for key in purchase_levels.keys():
		if key.begins_with("inf_"):
			total_count += purchase_levels[key]
	last_calculated_total_infusions = total_count
	return total_count


## Milestone Check: Verifies if a milestone token allows a custom specialty payload card.
func is_specialty_card_allowed() -> bool:
	# Earned tokens clamp arithmetically: 1 token at 3, 2 tokens at 6, 3 tokens at 9 infusions.
	var earned_tokens = clampi(last_calculated_total_infusions / 3, 0, 3)
	return specialty_cards_purchased < earned_tokens


## Core Evaluation Gate: Locks or unlocks row allocation buttons on the UI interface.
func is_infusion_card_allowed(
	definition: UpgradeDefinition, 
	state: int, 
	is_overclocked: bool, 
	purchase_levels: Dictionary[String, int]
) -> bool:
	# If this card isn't an elemental socket type, skip evaluation filters blindly
	if not definition.tags.has(Tags.Type.INFUSION): 
		return true 
		
	var target_upgrade_id: String = definition.upgrade_id
	var current_element_level: int = purchase_levels.get(target_upgrade_id, 0)
	
	# --- OVERCLOCK ENGINE BYPASS ---
	# If permanently overclocked or in a stabilized hybrid fallback state, standard soft caps shatter!
	if is_overclocked: 
		return current_element_level < INFUSION_HARD_CAP

	# Count how many individual physical element sockets are currently occupied (Level > 0).
	var active_socket_count: int = 0
	for key in purchase_levels.keys():
		if key.begins_with("inf_") and purchase_levels[key] > 0:
			active_socket_count += 1
			
	# --- MULTI-TIERPROGRESSION PROGRESSION GATING RULES ---
	match state:
		0: # TIER_1_BASE
			# Gate Rule A: An element track cannot exceed Level 3.
			# Gate Rule B: A completely new element cannot be added if 2 unique elements are already socketed.
			if current_element_level >= INFUSION_SOFT_CAP_T1: 
				return false
			if current_element_level == 0 and active_socket_count >= 2: 
				return false
				
		1: # TIER_2_EVOLVED
			# Gate Rule A: An element track cannot exceed Level 5.
			# Gate Rule B: Opens a 3rd socket slot layout, blocking a 4th unique element.
			if current_element_level >= INFUSION_SOFT_CAP_T2: 
				return false
			if current_element_level == 0 and active_socket_count >= 3: 
				return false
				
		2: # TIER_3_APEX
			# Final legendary form allows all active element sockets to scale up to Level 5.
			if current_element_level >= INFUSION_SOFT_CAP_T2: 
				return false
			
	return true
