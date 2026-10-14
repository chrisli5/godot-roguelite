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

## Allocation-free modifier aggregation for ONE stat on ONE hotbar slot.
## Returns Vector3(flat_sum, percent_sum, multiplicative_product). Slot 0 is the Character Core.
## The multiplicative product starts at 1.0 and multiplies (1 + value)^tier per upgrade.
## Final stat formula: (base + flat) * (1 + percent) * multiplicative.
func get_modifier_totals(slot_index: int, weapon_tags: Array[Tags.Type], stat_type: Stat.Type) -> Vector3:
	var flat_sum := 0.0
	var percent_sum := 0.0
	var multiplicative_product := 1.0

	for def in active_upgrades:
		var payload := def.stat_modifier_payload
		if payload == null or payload.target_stat_type != stat_type:
			continue

		var tier := _resolve_tier(def, slot_index, weapon_tags)
		if tier <= 0:
			continue

		if payload.type == StatModifier.Type.FLAT:
			flat_sum += payload.value * tier
		elif payload.type == StatModifier.Type.PERCENT:
			percent_sum += payload.value * tier
		elif payload.type == StatModifier.Type.MULTIPLICATIVE:
			multiplicative_product *= pow(1.0 + payload.value, tier)

	return Vector3(flat_sum, percent_sum, multiplicative_product)


## Status effects carried by the upgrades that apply to this slot, in purchase order.
## A card only needs to be present (tier > 0); extra copies add nothing. Deduplicated by
## effect_id, first wins.
func get_status_effects(slot_index: int, weapon_tags: Array[Tags.Type]) -> Array[StatusEffect]:
	var effects: Array[StatusEffect] = []

	for def in active_upgrades:
		var status := def.status_effect_payload
		if status == null:
			continue
		if _resolve_tier(def, slot_index, weapon_tags) <= 0:
			continue

		var already_present := false
		for existing in effects:
			if existing.effect_id == status.effect_id:
				already_present = true
				break
		if not already_present:
			effects.append(status)

	return effects


## Returns how many tiers of `def` apply to this slot (0 = not eligible).
func _resolve_tier(def: UpgradeDefinition, slot_index: int, weapon_tags: Array[Tags.Type]) -> int:
	# LAYER A: slot-specific purchases (e.g. infusions) always win for their own lane
	var slot_key := "%s::slot_%d" % [def.upgrade_id, slot_index]
	if purchase_registry.has(slot_key):
		return purchase_registry[slot_key]

	# LAYER B: standard purchases, filtered by the definition's scope
	var tier: int = purchase_registry.get(def.upgrade_id, 0)
	if tier <= 0:
		return 0

	match def.scope:
		UpgradeDefinition.ScopeType.CHARACTER_CORE:
			return tier if slot_index == 0 else 0
		UpgradeDefinition.ScopeType.LOCAL_SLOT:
			return tier if def.restrict_to_slot == slot_index else 0
		UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH:
			for required_tag in def.target_tags:
				if weapon_tags.has(required_tag):
					return tier
	return 0


## Replaces the ledger contents with a saved run (used when a new room spawns the player).
## Deliberately silent: restoring must not replay purchase side effects or unlock logic.
func restore_state(saved_registry: Dictionary, saved_upgrades: Array) -> void:
	purchase_registry.clear()
	for upgrade_id in saved_registry:
		purchase_registry[upgrade_id] = int(saved_registry[upgrade_id])

	active_upgrades.clear()
	for definition in saved_upgrades:
		active_upgrades.append(definition)

	ui_inventory_updated.emit()
