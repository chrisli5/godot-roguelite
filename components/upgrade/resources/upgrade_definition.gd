# res://components/upgrade/resources/upgrade_definition.gd
class_name UpgradeDefinition
extends Resource

## Append-only: stored as integers in .tres files.
enum PayloadType { STAT_MODIFIER, ABILITY_UNLOCK, ABILITY_OVERCLOCK }

enum ScopeType {
	CHARACTER_CORE,    # Targets player baseline character stats (e.g., Max Health, Move Speed)
	LOCAL_SLOT,        # Targets a specific hotbar weapon lane directly (Slot 1, 2, 3...)
	GLOBAL_TAG_MATCH   # Broadly targets ANY weapon possessing matching taxonomy tags (e.g., PROJECTILE)
}

## What kind of card this is. Append-only: stored as an integer in .tres files.
## INFUSION cards are socketed into an ability slot and decide that slot's infusion level.
enum Category { GENERAL, INFUSION }

@export_group("Identification")
@export var upgrade_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.GENERAL

@export_group("Targeting Architecture & Scope")
## Dictates how this upgrade scales and filters across your character core or hotbar weapons.
@export var scope: ScopeType = ScopeType.CHARACTER_CORE
## Only evaluated if scope is set to LOCAL_SLOT. Restricts which hotbar slot lane index can absorb this.
@export var restrict_to_slot: int = 0
## Only evaluated if scope is set to GLOBAL_TAG_MATCH. (e.g., applying to any weapon featuring Tags.Type.FIRE)
@export var target_tags: Array[Tags.Type] = []

@export_group("Payload Configuration")
@export var payload_type: PayloadType = PayloadType.STAT_MODIFIER
## Every stat modifier this card carries, in order. Read through get_stat_modifiers().
@export var stat_modifiers: Array[StatModifier] = []
## Superseded by `stat_modifiers`; will be removed in a later task. Used only while `stat_modifiers` is empty.
@export var stat_modifier_payload: StatModifier
## Superseded by `stat_modifiers`; will be removed in a later task. Used only while `stat_modifiers` is empty.
## Extra stat modifiers carried by the same card, resolved by the ledger exactly like stat_modifier_payload.
@export var additional_stat_modifiers: Array[StatModifier] = []
@export var ability_data_payload: AbilityData
## Optional status applied by hits from abilities this card applies to. Independent of payload_type,
## so a card can carry a stat modifier and a status together.
@export var status_effect_payload: StatusEffect
## Optional impact burst fired by hits from abilities this card applies to (chosen at cast time).
@export var impact_burst_payload: ImpactBurstDefinition

@export_group("Evolution Gating")
## Only used by ABILITY_UNLOCK cards that are evolutions: the base ability this card evolves.
## Null for ordinary unlocks (which are drafted normally).
@export var evolves_from: AbilityData
## Elements that must all be at the current soft cap for this evolution to be offered.
@export var recipe_requirements: Array[Tags.Type] = []


# Bridge cache for cards that still use the old fields: the list built from them, and what it was built from.
var _legacy_modifiers: Array[StatModifier] = []
var _legacy_primary_seen: StatModifier = null
var _legacy_extras_seen: Array[StatModifier] = []
var _legacy_built: bool = false


## The stat modifiers this card carries, in order. Returns `stat_modifiers` itself (no copy) when it is not empty;
## otherwise the legacy list: `stat_modifier_payload` first (if set), then `additional_stat_modifiers` without nulls.
## The legacy list is cached and rebuilt only when the old fields changed (compared by reference), so a steady-state
## call does not allocate. Callers must not modify the returned array.
func get_stat_modifiers() -> Array[StatModifier]:
	if not stat_modifiers.is_empty():
		return stat_modifiers
	if not _is_legacy_cache_current():
		_rebuild_legacy_cache()
	return _legacy_modifiers


func _is_legacy_cache_current() -> bool:
	if not _legacy_built or _legacy_primary_seen != stat_modifier_payload:
		return false
	var count := additional_stat_modifiers.size()
	if _legacy_extras_seen.size() != count:
		return false
	for i in range(count):
		if _legacy_extras_seen[i] != additional_stat_modifiers[i]:
			return false
	return true


func _rebuild_legacy_cache() -> void:
	_legacy_modifiers = []
	if stat_modifier_payload != null:
		_legacy_modifiers.append(stat_modifier_payload)
	for extra in additional_stat_modifiers:
		if extra != null:
			_legacy_modifiers.append(extra)
	_legacy_primary_seen = stat_modifier_payload
	_legacy_extras_seen = additional_stat_modifiers.duplicate()
	_legacy_built = true


## True if this card is an elemental socket infusion (decided by `category`, not by the id).
func is_infusion() -> bool:
	return category == Category.INFUSION


## Extracted element positioning slot lookup pass matching rigid enum flags
func get_infusion_element() -> Tags.Type:
	if not is_infusion():
		return Tags.Type.NONE
	
	# Scans target_tags directly to figure out what element this infusion maps to
	for tag in target_tags:
		if Tags.get_index_from_element(tag) != -1:
			return tag
			
	return Tags.Type.NONE
