class_name RunLedgerComponent
extends Node

## Emitted whenever any upgrade purchase transaction locks down, allowing UIs to redraw dynamically
signal ui_inventory_updated
signal stats_invalidated(definition: UpgradeDefinition)

## Single source of truth dictionary tracking card investment levels: {"player_movement_speed": 3}
var purchase_registry: Dictionary[String, int] = {}

## Array keeping tracking references to all definitions unlocked/drafted during the run
var active_upgrades: Array[UpgradeDefinition] = []


## Records a card purchase or tier increase directly inside central RAM memory.
func log_purchase(definition: UpgradeDefinition) -> void:
	if not is_instance_valid(definition): 
		return
	
	var upgrade_id := definition.upgrade_id
	if not purchase_registry.has(upgrade_id):
		purchase_registry[upgrade_id] = 0
		active_upgrades.append(definition)
		
	purchase_registry[upgrade_id] += 1
	ui_inventory_updated.emit()
	stats_invalidated.emit(definition)


## MASTER EVALUATOR: Compiles dynamically scaled runtime modifiers matching 
## a specific weapon's hotbar slot context index and live taxonomy tags array.
func compile_modifiers_for_weapon(slot_index: int, weapon_tags: Array[Tags.Type]) -> Array[StatModifier]:
	var compiled_list: Array[StatModifier] = []
	
	for def in active_upgrades:
		var tier = purchase_registry.get(def.upgrade_id, 0)
		if tier <= 0: 
			continue
		
		var is_eligible := false
		
		match def.scope:
			UpgradeDefinition.ScopeType.LOCAL_SLOT:
				# Direct Target: Does this card explicitly target this weapon's lane?
				if def.restrict_to_slot == slot_index:
					is_eligible = true
					
			UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH:
				# Taxonomy Match: Does the calling weapon possess the tags targeted by this card?
				for required_tag in def.target_tags:
					if weapon_tags.has(required_tag):
						is_eligible = true
						break # Found a match, break early
						
		if is_eligible and is_instance_valid(def.stat_modifier_payload):
			# Create a clean, dynamically scaled runtime modifier block instance
			var runtime_mod: StatModifier = def.stat_modifier_payload.duplicate()
			runtime_mod.value = def.stat_modifier_payload.value * tier
			# Deterministic unique ID to prevent overlap collisions
			runtime_mod.id = "ledger::" + def.upgrade_id
			compiled_list.append(runtime_mod)
			
	return compiled_list
