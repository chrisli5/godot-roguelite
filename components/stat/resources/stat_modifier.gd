class_name StatModifier
extends Resource

enum Type { FLAT, PERCENT }

@export var type: Type = Type.FLAT
@export var value: float = 0.0
@export var target_stat_type: Stat.Type = Stat.Type.MAX_HEALTH
# IDs are automatically generated at runtime using ModifierFactory.
var id: String = "transient_modifier"
