class_name UpgradeDefinition
extends Resource

enum PayloadType { STAT_MODIFIER, ABILITY_UNLOCK }

@export_group("Identification")
@export var upgrade_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export var draft_behavior_tags: Array[Tags.Type] = []
@export var recipe_requirements: Array[Tags.Type]
@export var global_modifier_tags: Array[Tags.Type] = []

@export_group("Payload Configuration")
@export var payload_type: PayloadType = PayloadType.STAT_MODIFIER
@export var stat_modifier_payload: StatModifier
@export var target_stat_type: Stat.Type
@export var ability_data_payload: AbilityData

func is_infusion() -> bool:
	return draft_behavior_tags.has(Tags.Type.INFUSION)


func get_infusion_element() -> Tags.Type:
	if not is_infusion():
		return Tags.Type.NONE
	
	for tag in draft_behavior_tags:
		if Tags.get_index_from_element(tag) != -1:
			return tag
			
	return Tags.Type.NONE
