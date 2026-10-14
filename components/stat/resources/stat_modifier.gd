class_name StatModifier
extends Resource

## MULTIPLICATIVE: value v at tier t contributes (1 + v)^t; contributions multiply together.
enum Type { FLAT, PERCENT, MULTIPLICATIVE }

@export var type: Type = Type.FLAT
@export var value: float = 0.0
@export var target_stat_type: Stat.Type = Stat.Type.MAX_HEALTH
# IDs are automatically generated at runtime using ModifierFactory.
var id: String = "transient_modifier"
