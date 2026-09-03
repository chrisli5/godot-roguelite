class_name Ability
extends Node2D

@export var stats_container: StatsContainer
@export var upgrade_ledger_component: UpgradeLedgerComponent
@export var infusion_tracker_component: InfusionTrackerComponent
@export var evolution_gate_component: EvolutionGateComponent
@export var tag_component: TagComponent

var display_name: String = ""


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
	
	var purchase_records: Dictionary[String, int] = upgrade_ledger_component.purchase_levels
	var raw_evo_blueprints: Array[UpgradeTracker] = upgrade_ledger_component.available_evolutions
	var active_tags: Array[Tags.Type] = tag_component.get_active_tags() if is_instance_valid(tag_component) else []
	
	# --- PHASE 1: COMPILE STRUCTURAL RECIPES THROUGH THE FILTER PIPE ---
	if is_instance_valid(evolution_gate_component):
		if is_instance_valid(infusion_tracker_component):
			infusion_tracker_component.calculate_total_infusions(purchase_records)
			
		# Pass the raw ledger arrays into the pure processing filter method
		compiled_evolutions = evolution_gate_component.evaluate_evolution_recipes(raw_evo_blueprints, purchase_records, active_tags)
		
	var has_active_evolutions: bool = not compiled_evolutions.is_empty()

	# --- PHASE 2: COMPILE LINEAR STAT UPGRADE CARDS ---
	for tracker in upgrade_ledger_component.available_upgrades:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases: 
			continue
		
		# Validate active socket boundaries and constraints
		if is_instance_valid(infusion_tracker_component):
			if definition.has_meta("specialty_payload"):
				if not infusion_tracker_component.is_specialty_card_allowed(): 
					continue
			else:
				if player_character_level < tracker.required_character_level: 
					continue
			
			var state_gate = int(evolution_gate_component.current_state) if is_instance_valid(evolution_gate_component) else 0
			var is_oc = evolution_gate_component.is_permanently_overclocked if is_instance_valid(evolution_gate_component) else false
			var is_hybrid_overclocked: bool = (not has_active_evolutions)
			
			if not infusion_tracker_component.is_infusion_card_allowed(definition, state_gate, is_oc or is_hybrid_overclocked, purchase_records):
				continue
		else:
			if player_character_level < tracker.required_character_level: 
				continue
			
		var current_acquired_tier = purchase_records.get(definition.upgrade_id, 0)
		if tracker.tier_index == current_acquired_tier + 1: 
			compiled_upgrades.append(tracker)

	# --- PHASE 3: WRITE BACK TO THE STORAGE REGISTERS ---
	upgrade_ledger_component.clear_caches()
	upgrade_ledger_component.overwrite_cached_pools(compiled_upgrades, compiled_evolutions)


func apply_evolution_mutation(_choice: UpgradeChoice) -> void:
	if is_instance_valid(evolution_gate_component):
		evolution_gate_component.advance_evolution_state()


func apply_infusion_socket(element_tag: Tags.Type, upgrade_id: String) -> void:
	# 1. Update the pure physics/combat execution tags string-free
	if is_instance_valid(tag_component):
		tag_component.add_tag(element_tag)
		tag_component.add_tag(Tags.Type.INFUSION)

	# 2. Update the progress accounting ledger
	if is_instance_valid(upgrade_ledger_component):
		upgrade_ledger_component.log_purchase_entry(upgrade_id)

	# 3. Inform the infusion tracker to audit new totals and validate socket boundaries
	if is_instance_valid(infusion_tracker_component) and is_instance_valid(upgrade_ledger_component):
		infusion_tracker_component.calculate_total_infusions(upgrade_ledger_component.purchase_levels)

	print("[SOCKET] %s successfully socketed into %s" % [upgrade_id, display_name])


func _on_stat_updated(_stat_type: Stat.Type, _new_value: float) -> void:
	pass
