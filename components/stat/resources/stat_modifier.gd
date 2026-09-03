class_name StatModifier
extends Resource

enum Type { FLAT, PERCENT }

@export var type: Type = Type.FLAT
@export var value: float = 0.0

# IDs are automatically generated at runtime using ModifierFactory.
var id: String = "transient_modifier"
