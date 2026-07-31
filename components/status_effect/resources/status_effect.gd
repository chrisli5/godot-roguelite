# res://components/status_effect_system/resources/status_effect.gd
class_name StatusEffect
extends Resource

@export var effect_id: String = ""
@export var target_stat_type: Stat.Type
@export var target_ability_id: int
@export var duration: float = 5.0
@export var modifier: StatModifier
