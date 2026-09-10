class_name InfusionTrackerComponent
extends Node

const INFUSION_SOFT_CAP_T1: int = 3
const INFUSION_SOFT_CAP_T2: int = 5
const INFUSION_HARD_CAP: int = 15

var specialty_cards_purchased: int = 0
var last_calculated_total_infusions: int = 0

# --- THE HOSED INDEPENDENT REGISTER REGISTER ---
# Position 0 = Fire, 1 = Frost, 2 = Lightning, 3 = Wind, 4 = Earth
var infusion_levels: Array[int] = [0, 0, 0, 0, 0]


func get_index_from_element(element_tag: Tags.Type) -> int:
	match element_tag:
		Tags.Type.SOCKET_FIRE: return 0
		Tags.Type.SOCKET_FROST: return 1
		Tags.Type.SOCKET_LIGHTNING: return 2
		Tags.Type.SOCKET_WIND: return 3
		Tags.Type.SOCKET_EARTH: return 4
		_: return -1


## Public Command Hook: Increments and updates levels locally string-free
func record_socket_transaction(element_tag: Tags.Type) -> void:
	var idx = get_index_from_element(element_tag)
	if idx != -1:
		infusion_levels[idx] += 1
		_recalculate_totals()


func _recalculate_totals() -> void:
	var total_count: int = 0
	for level in infusion_levels:
		total_count += level
	last_calculated_total_infusions = total_count


#func is_specialty_card_allowed() -> bool:
	#var earned_tokens = clampi(last_calculated_total_infusions / 3, 0, 3)
	#return specialty_cards_purchased < earned_tokens


## Streamlined String-Free Gating Checker Pass
func is_element_socket_allowed(selected_element: Tags.Type, state: int, is_overclocked: bool) -> bool:
	var element_index = get_index_from_element(selected_element)
	print("ele_index: ", element_index)
	if element_index == -1: 
		return false
		
	var current_element_level = infusion_levels[element_index]
	
	if is_overclocked:
		return current_element_level < INFUSION_HARD_CAP

	# Count occupied physical lanes (Level > 0)
	var active_socket_count: int = 0
	for level in infusion_levels:
		if level > 0:
			active_socket_count += 1
			
	match state:
		0: # EvolutionState.TIER_1_BASE
			if current_element_level > 0:
				return current_element_level < INFUSION_SOFT_CAP_T1
			return active_socket_count < 2
			
		1: # EvolutionState.TIER_2_EVOLVED
			if current_element_level > 0:
				return current_element_level < INFUSION_SOFT_CAP_T2
			return active_socket_count < 3
			
		2: # EvolutionState.TIER_3_APEX:
			return current_element_level < INFUSION_SOFT_CAP_T2
	
	return true
