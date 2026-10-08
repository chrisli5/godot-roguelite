class_name RunLedgerComponent
extends Node


signal ui_inventory_updated
signal stats_invalidated(definition: UpgradeDefinition)

var purchase_registry: Dictionary[String, int] = {}
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


func log_slot_specific_purchase(definition: UpgradeDefinition, chosen_slot_idx: int) -> void:
	if not is_instance_valid(definition): return
	
	var specialized_id := "%s::slot_%d" % [definition.upgrade_id, chosen_slot_idx]
	if not purchase_registry.has(specialized_id):
		purchase_registry[specialized_id] = 0
		if not active_upgrades.has(definition):
			active_upgrades.append(definition)
			
	purchase_registry[specialized_id] += 1
	ui_inventory_updated.emit()
	stats_invalidated.emit(definition)

## MASTER EVALUATOR: Compiles dynamically scaled runtime modifiers matching 
## a specific weapon's hotbar slot context index and live taxonomy tags array.
func compile_modifiers_for_weapon(slot_index: int, weapon_tags: Array[Tags.Type]) -> Array[StatModifier]:
	var compiled_list: Array[StatModifier] = []
	
	for def in active_upgrades:
		# --- LAYER A: CHECK FOR OPEN-ENDED SLOT-SPECIFIC INFUSIONS ---
		var specialized_id := "%s::slot_%d" % [def.upgrade_id, slot_index]
		var tier = 0
		var is_eligible := false
		
		if purchase_registry.has(specialized_id):
			tier = purchase_registry[specialized_id]
			is_eligible = true
		else:
			# --- LAYER B: FALLBACK TO STANDARD FIXED SCOPE EVALUATION ---
			tier = purchase_registry.get(def.upgrade_id, 0)
			if tier > 0:
				match def.scope:
					UpgradeDefinition.ScopeType.LOCAL_SLOT:
						if def.restrict_to_slot == slot_index:
							is_eligible = true
					UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH:
						for required_tag in def.target_tags:
							if weapon_tags.has(required_tag):
								is_eligible = true
								break
								
		# If any architectural tier evaluation matches out, append the scaled modifier block
		if is_eligible and tier > 0 and is_instance_valid(def.stat_modifier_payload):
			var runtime_mod: StatModifier = def.stat_modifier_payload.duplicate()
			runtime_mod.value = def.stat_modifier_payload.value * tier
			
			# Generate a deterministic unique ID based on the resolved registry key namespace
			var resolved_id := specialized_id if purchase_registry.has(specialized_id) else def.upgrade_id
			runtime_mod.id = "ledger::" + resolved_id
			
			compiled_list.append(runtime_mod)
			
	return compiled_list
