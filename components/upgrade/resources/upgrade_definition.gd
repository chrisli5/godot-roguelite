# res://components/upgrade/resources/upgrade_definition.gd
class_name UpgradeDefinition
extends Resource

enum PayloadType { STAT_MODIFIER, ABILITY_UNLOCK }

enum ScopeType {
	CHARACTER_CORE,    # Targets player baseline character stats (e.g., Max Health, Move Speed)
	LOCAL_SLOT,        # Targets a specific hotbar weapon lane directly (Slot 1, 2, 3...)
	GLOBAL_TAG_MATCH   # Broadly targets ANY weapon possessing matching taxonomy tags (e.g., PROJECTILE)
}

@export_group("Identification")
@export var upgrade_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Targeting Architecture & Scope")
## Dictates how this upgrade scales and filters across your character core or hotbar weapons.
@export var scope: ScopeType = ScopeType.CHARACTER_CORE
## Only evaluated if scope is set to LOCAL_SLOT. Restricts which hotbar slot lane index can absorb this.
@export var restrict_to_slot: int = 0
## Only evaluated if scope is set to GLOBAL_TAG_MATCH. (e.g., applying to any weapon featuring Tags.Type.FIRE)
@export var target_tags: Array[Tags.Type] = []

@export_group("Draft Behavior Legacy Properties")
@export var draft_behavior_tags: Array[Tags.Type] = []
@export var recipe_requirements: Array[Tags.Type] = []
@export var global_modifier_tags: Array[Tags.Type] = []

@export_group("Payload Configuration")
@export var payload_type: PayloadType = PayloadType.STAT_MODIFIER
@export var stat_modifier_payload: StatModifier
@export var target_stat_type: Stat.Type
@export var ability_data_payload: AbilityData


## Helper utility checking if this card behaves as an elemental socket infusion
func is_infusion() -> bool:
	return draft_behavior_tags.has(Tags.Type.INFUSION)


## Extracted element positioning slot lookup pass matching rigid enum flags
func get_infusion_element() -> Tags.Type:
	if not is_infusion():
		return Tags.Type.NONE
	
	for tag in draft_behavior_tags:
		if Tags.get_index_from_element(tag) != -1:
			return tag
			
	return Tags.Type.NONE
