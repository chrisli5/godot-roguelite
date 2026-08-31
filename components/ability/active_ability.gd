class_name ActiveAbility
extends Node2D

@export_group("Decoupled Sub-Modules")
@export var upgrade_ledger: UpgradeLedgerComponent
@export var infusion_tracker: InfusionTrackerComponent
@export var evolution_gate: EvolutionGateComponent
@export var tag_component: TagComponent

var display_name: String = "Arcane Needle"
var ability_id: int = 0


func _ready() -> void:
	# Bind our parent listener pass to intercept the gate execution results
	if is_instance_valid(evolution_gate):
		evolution_gate.caches_rebuilt.connect(_on_gate_caches_rebuilt)


## The central compilation bridge requested by the UpgradeManager
func trigger_cache_rebuild(player_character_level: int) -> void:
	if not is_instance_valid(upgrade_ledger) or not is_instance_valid(evolution_gate):
		return
		
	var active_tags = tag_component.get_active_tags() if is_instance_valid(tag_component) else []
	
	# Update localized infusion metrics tracking frames prior to processing passes
	if is_instance_valid(infusion_tracker):
		infusion_tracker.calculate_total_infusions(upgrade_ledger.purchase_levels)
		
	# MEDIATION PASS: Extract data from ledger and stream it explicitly down to the gate module
	evolution_gate.process_cache_evaluation(
		upgrade_ledger.available_upgrades,
		upgrade_ledger.purchase_levels,
		active_tags,
		player_character_level,
		infusion_tracker
	)


func _on_gate_caches_rebuilt(compiled_upgrades: Array[UpgradeTracker], compiled_evolutions: Array[UpgradeTracker]) -> void:
	# MEDIATION PASS: Write calculated arrays back safely into ledger cache storage registers
	if is_instance_valid(upgrade_ledger):
		upgrade_ledger.clear_caches()
		for tracker in compiled_upgrades:
			upgrade_ledger.append_to_upgrades_cache(tracker)
		for tracker in compiled_evolutions:
			upgrade_ledger.append_to_evolutions_cache(tracker)


func apply_evolution_mutation(choice: UpgradeChoice) -> void:
	if is_instance_valid(evolution_gate):
		evolution_gate.advance_evolution_state()
	# Apply visual mesh adjustments or projectile property variations smoothly here...
