class_name Ability
extends Node2D

@export var stats_container: StatsContainer
@export var upgrade_ledger_component: UpgradeLedgerComponent
@export var infusion_tracker_component: InfusionTrackerComponent
@export var evolution_gate_component: EvolutionGateComponent
@export var tag_component: TagComponent

var display_name: String = ""
var is_eligible_for_overclock: bool = false


func _ready() -> void:
	var required_ability_components: Array[String] = [
		"stats_container",
		"upgrade_ledger_component",
		"infusion_tracker_component",
		"evolution_gate_component",
		"tag_component"
	]
	
	if not ValidationUtility.validate_components(self, required_ability_components):
		set_physics_process(false)
		return
	
	if is_instance_valid(stats_container):
		stats_container.stat_updated.connect(_on_stat_updated)


func compile_eligible_pool(player_character_level: int) -> void:
	if not is_instance_valid(upgrade_ledger_component):
		return
		
	var compiled_upgrades: Array[UpgradeTracker] = []
	var compiled_evolutions: Array[UpgradeTracker] = []
	
	var raw_evo_blueprints: Array[UpgradeTracker] = upgrade_ledger_component.available_evolutions
	var active_tags: Array[Tags.Type] = tag_component.get_active_tags() if is_instance_valid(tag_component) else []
	
	# Reset the state flag before evaluating the current frame pass
	is_eligible_for_overclock = false

	# --- PHASE 1: EVALUATE STRUCTURAL RECIPES THROUGH THE EVO ENGINE ---
	if is_instance_valid(evolution_gate_component) and is_instance_valid(infusion_tracker_component):
		# SYNCED PASS: Evaluates hand-crafted recipes passing the type-safe integer array directly
		compiled_evolutions = evolution_gate_component.evaluate_evolution_recipes(
			raw_evo_blueprints, 
			infusion_tracker_component.infusion_levels, 
			active_tags
		)
		
		# --- DATA-DRIVEN OVERCLOCK ELIGIBILITY STATE AUDIT ---
		# Determine if the weapon's socket arrays have collectively arrived at a soft cap ceiling
		var active_sockets: int = 0
		var capped_elements: int = 0
		var soft_cap_target = 3 if evolution_gate_component.current_state == EvolutionGateComponent.EvolutionState.TIER_1_BASE else 5
		
		for level in infusion_tracker_component.infusion_levels:
			if level > 0:
				active_sockets += 1
				if level >= soft_cap_target:
					capped_elements += 1
					
		var is_at_soft_cap = (active_sockets >= 2 and capped_elements >= 2) if evolution_gate_component.current_state == EvolutionGateComponent.EvolutionState.TIER_1_BASE else (active_sockets >= 3 and capped_elements >= 3)
		
		# Expose the boolean state flag; if true, the UpgradeManager injects the disk-based Overclock tracker
		if is_at_soft_cap and not evolution_gate_component.is_permanently_overclocked:
			is_eligible_for_overclock = true
			
			# Pull the persistent Overclock variant scene swap tracker straight from disk storage configurations
			var ovr_track = upgrade_ledger_component.overclock_tracker
			if is_instance_valid(ovr_track) and ovr_track.current_purchases < ovr_track.max_purchases:
				compiled_evolutions.append(ovr_track)
		
	# --- PHASE 2: COMPILE LINEAR WEAPON STAT MODIFIERS ---
	for tracker in upgrade_ledger_component.available_upgrades:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases: 
			continue
		
		# Dynamic level step gating calculation pass (Single Value Scaling integration)
		var dynamic_req_level = tracker.required_character_level + (tracker.current_purchases * 2)
		if player_character_level < dynamic_req_level: 
			continue
			
		# Synchronize card text tier number display properties smoothly (e.g., Cooldown Rate III)
		tracker.tier_index = tracker.current_purchases + 1
		compiled_upgrades.append(tracker)

	# --- PHASE 3: WRITE BACK TO THE LOCAL VIEW CACHE REGISTERS ---
	upgrade_ledger_component.clear_caches()
	upgrade_ledger_component.overwrite_cached_pools(compiled_upgrades, compiled_evolutions)


func apply_evolution_mutation(_choice: UpgradeChoice) -> void:
	if is_instance_valid(evolution_gate_component):
		evolution_gate_component.advance_evolution_state()


func apply_infusion_socket(element_tag: Tags.Type, _upgrade_id: String) -> void:
	# 1. Update strict identity categorization rules safely via tag component
	if is_instance_valid(tag_component):
		tag_component.add_tag(element_tag)
		tag_component.add_tag(Tags.Type.INFUSION)

	# 2. Directly instruct the independent module to record progress levels string-free
	if is_instance_valid(infusion_tracker_component):
		infusion_tracker_component.record_socket_transaction(element_tag)

	print("[SOCKET] %s successfully registered inside local module layers." % Tags.Type.keys()[element_tag])


func _on_stat_updated(_stat_type: Stat.Type, _new_value: float) -> void:
	pass
