# res://components/ability/infusion_tracker_component.gd
class_name InfusionTrackerComponent
extends Node

const INFUSION_SOFT_CAP_T1: int = 3
const INFUSION_SOFT_CAP_T2: int = 5
const INFUSION_HARD_CAP: int = 15

var last_calculated_total_infusions: int = 0
var infusion_levels: Array[int] = [0, 0, 0, 0, 0]


func record_socket_transaction(element_tag: Tags.Type) -> void:
	var idx = Tags.get_index_from_element(element_tag)
	if idx != -1:
		infusion_levels[idx] += 1
		_recalculate_totals()


func _recalculate_totals() -> void:
	var total_count: int = 0
	for level in infusion_levels:
		total_count += level
	last_calculated_total_infusions = total_count


## Refactored: Leverages explicit type-safe EvolutionState boundaries
func is_element_socket_allowed(selected_element: Tags.Type, state: EvolutionGateComponent.EvolutionState, is_overclocked: bool) -> bool:
	var element_index = Tags.get_index_from_element(selected_element)
	if element_index == -1: 
		return false
		
	var current_element_level = infusion_levels[element_index]
	
	if is_overclocked:
		return current_element_level < INFUSION_HARD_CAP

	var active_socket_count: int = 0
	for level in infusion_levels:
		if level > 0:
			active_socket_count += 1
			
	match state:
		EvolutionGateComponent.EvolutionState.TIER_1_BASE:
			if current_element_level > 0:
				return current_element_level < INFUSION_SOFT_CAP_T1
			return active_socket_count < 2
			
		EvolutionGateComponent.EvolutionState.TIER_2_EVOLVED:
			if current_element_level > 0:
				return current_element_level < INFUSION_SOFT_CAP_T2
			return active_socket_count < 3
			
		EvolutionGateComponent.EvolutionState.TIER_3_APEX:
			return current_element_level < INFUSION_SOFT_CAP_T2
	
	return true
