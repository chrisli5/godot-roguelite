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
	
	var specialized_id := PurchaseKey.make(definition.upgrade_id, chosen_slot_idx)
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
		# Tier is resolved lazily, only once a modifier of this card targets the stat.
		var tier := -1
		for modifier in def.stat_modifiers:
			if modifier == null or modifier.target_stat_type != stat_type:
				continue
			if tier < 0:
				tier = get_card_tier(def, slot_index, weapon_tags)
			if tier <= 0:
				break
			var contribution := _modifier_contribution(modifier, tier)
			flat_sum += contribution.x
			percent_sum += contribution.y
			multiplicative_product *= contribution.z

	return Vector3(flat_sum, percent_sum, multiplicative_product)


## One modifier's effect at `tier` as Vector3(flat_add, percent_add, multiplicative_factor).
func _modifier_contribution(modifier: StatModifier, tier: int) -> Vector3:
	match modifier.type:
		StatModifier.Type.FLAT:
			return Vector3(modifier.value * tier, 0.0, 1.0)
		StatModifier.Type.PERCENT:
			return Vector3(0.0, modifier.value * tier, 1.0)
		StatModifier.Type.MULTIPLICATIVE:
			return Vector3(0.0, 0.0, pow(1.0 + modifier.value, tier))
	return Vector3(0.0, 0.0, 1.0)


## Status effects carried by the upgrades that apply to this slot, in purchase order.
## A card only needs to be present (tier > 0); extra copies add nothing. Deduplicated by
## effect_id, first wins.
func get_status_effects(slot_index: int, weapon_tags: Array[Tags.Type]) -> Array[StatusEffect]:
	var effects: Array[StatusEffect] = []
	_collect_unique_payloads(slot_index, weapon_tags, _status_payload_of, _status_key_of, effects)
	return effects


## Impact bursts carried by the upgrades that apply to this slot, in purchase order. Resolved exactly
## like get_status_effects: a card only needs to be present, and bursts are deduplicated by burst_id
## (first wins).
func get_impact_bursts(slot_index: int, weapon_tags: Array[Tags.Type]) -> Array[ImpactBurstDefinition]:
	var bursts: Array[ImpactBurstDefinition] = []
	_collect_unique_payloads(slot_index, weapon_tags, _burst_payload_of, _burst_key_of, bursts)
	return bursts


## Indirect effects of the cards that apply to this slot whose level (the card's tier in the slot) has reached the
## effect's unlock level. Duplicate copies of a card add nothing: one effect per card.
func get_active_indirect_effects(slot_index: int, weapon_tags: Array[Tags.Type]) -> Array[IndirectEffectDefinition]:
	var effects: Array[IndirectEffectDefinition] = []
	for def in active_upgrades:
		if def.indirect_effect == null:
			continue
		if IndirectScaling.is_active(def.indirect_effect, get_card_tier(def, slot_index, weapon_tags)):
			effects.append(def.indirect_effect)
	return effects


## Walks the purchased cards in purchase order and appends each card's payload to `result`, skipping cards that
## do not apply to this slot (tier <= 0), null payloads, and payloads whose key was already added (first wins).
## `get_payload` maps a card to its payload (Callable(UpgradeDefinition) -> Resource); `get_key` maps a payload to its dedup key.
func _collect_unique_payloads(slot_index: int, weapon_tags: Array[Tags.Type], get_payload: Callable, get_key: Callable, result: Array) -> void:
	var seen_keys: Array[String] = []
	for def in active_upgrades:
		var payload := get_payload.call(def) as Resource
		if payload == null:
			continue
		if get_card_tier(def, slot_index, weapon_tags) <= 0:
			continue
		var key := String(get_key.call(payload))
		if seen_keys.has(key):
			continue
		seen_keys.append(key)
		result.append(payload)


func _status_payload_of(def: UpgradeDefinition) -> Resource:
	return def.status_effect_payload


func _status_key_of(payload: Resource) -> String:
	return (payload as StatusEffect).effect_id


func _burst_payload_of(def: UpgradeDefinition) -> Resource:
	return def.impact_burst_payload


func _burst_key_of(payload: Resource) -> String:
	return String((payload as ImpactBurstDefinition).burst_id)


## Infusion level of `element` in `slot_index`: the sum of the slot-specific tiers of every infusion card
## of that element. This is the single definition of an infusion level.
func get_infusion_level(slot_index: int, element: Tags.Type) -> int:
	var level := 0
	for def in active_upgrades:
		if def.is_infusion() and def.get_infusion_element() == element:
			level += purchase_registry.get(PurchaseKey.make(def.upgrade_id, slot_index), 0)
	return level


## Infusion levels of `slot_index` in element order (Tags.get_index_from_element: Fire, Frost, Lightning, Wind, Earth).
func get_infusion_levels(slot_index: int) -> Array[int]:
	var levels: Array[int] = [0, 0, 0, 0, 0]
	for def in active_upgrades:
		if not def.is_infusion():
			continue
		var element_index := Tags.get_index_from_element(def.get_infusion_element())
		if element_index != -1:
			levels[element_index] += purchase_registry.get(PurchaseKey.make(def.upgrade_id, slot_index), 0)
	return levels


## True when an Overclock card was bought for exactly this slot. Only the slot-specific key counts; a plain
## purchase overclocks nothing. This is the single definition of "overclocked".
func is_overclocked(slot_index: int) -> bool:
	for def in active_upgrades:
		if def.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK \
				and purchase_registry.get(PurchaseKey.make(def.upgrade_id, slot_index), 0) > 0:
			return true
	return false


## How many tiers of `def` apply to this slot (0 = not eligible). A slot-specific purchase beats the plain key and
## ignores the card's scope; the scope applies only to plain purchases. `weapon_tags` are the slot's PERMANENT tags
## (base and infusion tags, never temporary ones).
func get_card_tier(def: UpgradeDefinition, slot_index: int, weapon_tags: Array[Tags.Type]) -> int:
	# LAYER A: slot-specific purchases (e.g. infusions) always win for their own lane
	var slot_key := PurchaseKey.make(def.upgrade_id, slot_index)
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
