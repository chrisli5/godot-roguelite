class_name EvolutionGateComponent
extends Node

enum EvolutionState { TIER_1_BASE, TIER_2_EVOLVED, TIER_3_APEX }

var current_state: EvolutionState = EvolutionState.TIER_1_BASE
var is_permanently_overclocked: bool = false


func get_upgrade_id_from_element(element_tag: Tags.Type) -> String:
	match element_tag:
		Tags.Type.FIRE: return "inf_fire"
		Tags.Type.FROST: return "inf_frost"
		Tags.Type.WIND: return "inf_wind"
		Tags.Type.LIGHTNING: return "inf_lightning"
		_: return ""


## Pure Data Filter Pass: Sweeps across the array injected by the parent and returns valid results
func evaluate_evolution_recipes(available_evolutions: Array[UpgradeTracker], purchase_levels: Dictionary[String, int], active_tags: Array[Tags.Type]) -> Array[UpgradeTracker]:
	var eligible_evos: Array[UpgradeTracker] = []
	if is_permanently_overclocked or available_evolutions.is_empty():
		return eligible_evos

	# Highly streamlined loop: only sweeps across actual morphological definitions
	for tracker in available_evolutions:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases: 
			continue
		
		# Order-Agnostic Subset Check
		var recipe_satisfied = true
		for required_tag in definition.tags:
			if required_tag == Tags.Type.INFUSION: continue
			if not active_tags.has(required_tag):
				recipe_satisfied = false
				break
			if not recipe_satisfied: 
				continue

		# Horizontal Element Pacing Depth Check
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
			eligible_evos.append(tracker)
			
	return eligible_evos


func advance_evolution_state() -> void:
	if current_state == EvolutionState.TIER_1_BASE:
		current_state = EvolutionState.TIER_2_EVOLVED
	elif current_state == EvolutionState.TIER_2_EVOLVED:
		current_state = EvolutionState.TIER_3_APEX
