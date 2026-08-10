class_name UpgradeDefinition
extends Resource

enum PayloadType { STAT_MODIFIER, ABILITY_UNLOCK }

@export_group("Identification")
@export var upgrade_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var tags: Array[Tags.Type] = []

@export_group("Payload Configuration")
@export var payload_type: PayloadType = PayloadType.STAT_MODIFIER

## Used if payload_type is STAT_MODIFIER
@export var modifier: StatModifier
@export var target_stat_type: Stat.Type

## Used if payload_type is ABILITY_UNLOCK. 
@export var ability_scene_to_unlock: AbilityData
