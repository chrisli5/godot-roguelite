class_name StatModifier
extends Resource

enum Type { FLAT, PERCENT }

@export var id: String = "modifier_id"
@export var type: Type = Type.FLAT
@export var value: float = 0.0
