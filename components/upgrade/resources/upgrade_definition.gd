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
## Every stat modifier this card carries, in order. The ledger scales each one by the card's tier.
@export var stat_modifiers: Array[StatModifier] = []
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


@export_group("Compound")
## Compound cards only: the two elements whose pair this compound belongs to. Empty for every other card.
@export var compound_pair: Array[Tags.Type] = []


## True when `tags` (an ability's PERMANENT tags) contain ALL of this card's target_tags. A card with no
## target_tags never matches (it must not match everything vacuously). Used by GLOBAL_TAG_MATCH scope.
func matches_permanent_tags(tags: Array[Tags.Type]) -> bool:
	if target_tags.is_empty():
		return false
	for required_tag in target_tags:
		if not tags.has(required_tag):
			return false
	return true


## True if this card is a compound card (it names an element pair).
func is_compound_card() -> bool:
	return compound_pair.size() == 2


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
