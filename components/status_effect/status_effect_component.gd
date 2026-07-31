class_name StatusEffectComponent
extends Node

signal modifier_addition_requested(stat_type: Stat.Type, modifier: StatModifier, target_ability_id: int)
signal modifier_removal_requested(stat_type: Stat.Type, modifier: StatModifier, target_ability_id: int)


var _active_effects: Dictionary = {}


func _process(delta: float) -> void:
	if _active_effects.is_empty():
		return

	_update_effect_timers(delta)


func apply_effect(effect: StatusEffect) -> void:
	if not is_instance_valid(effect) or not is_instance_valid(effect.modifier):
		push_warning("StatusEffectComponent: Invalid status effect or modifier profile passed.")
		return

	if _active_effects.has(effect.effect_id):
		_active_effects[effect.effect_id]["time_remaining"] = effect.duration
		return

	_active_effects[effect.effect_id] = {
		"effect": effect,
		"time_remaining": effect.duration
	}

	modifier_addition_requested.emit(
		effect.target_stat_type, 
		effect.modifier, 
		effect.target_ability_id
	)


func _update_effect_timers(delta: float) -> void:
	var expired_ids: Array[String] = []
	
	for id in _active_effects:
		_active_effects[id]["time_remaining"] -= delta
		if _active_effects[id]["time_remaining"] <= 0.0:
			expired_ids.append(id)

	for id in expired_ids:
		_expire_effect(id)


func _expire_effect(id: String) -> void:
	if not _active_effects.has(id):
		return
		
	var data: Dictionary = _active_effects[id]
	var effect: StatusEffect = data["effect"]
	
	modifier_removal_requested.emit(
		effect.target_stat_type, 
		effect.modifier, 
		effect.target_ability_id
	)
	
	_active_effects.erase(id)
