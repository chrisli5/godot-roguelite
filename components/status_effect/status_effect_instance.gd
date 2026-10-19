class_name StatusEffectInstance
extends RefCounted
## Runtime state for ONE application of a StatusEffect template on ONE entity.

var template: StatusEffect
var instance_id: int = 0
var time_remaining: float = 0.0
var elapsed: float = 0.0
var tick_accumulator: float = 0.0
var stacks: int = 1

## Magnitudes snapshotted from the source's stats when the hit was generated.
var dot_damage: float = 0.0
var duration_bonus: float = 0.0
var ramp_cap_bonus: float = 0.0
var stack_cap_bonus: float = 0.0

## Per-application copies of the template's modifiers (unique ids, safe to mutate).
var runtime_modifiers: Array[StatModifier] = []


func _init(effect: StatusEffect, new_instance_id: int) -> void:
	template = effect
	instance_id = new_instance_id
	for template_modifier in effect.stat_modifiers:
		if not is_instance_valid(template_modifier):
			continue
		var runtime_modifier := template_modifier.duplicate() as StatModifier
		runtime_modifier.id = "%s#%d#%d" % [effect.effect_id, instance_id, runtime_modifiers.size()]
		runtime_modifiers.append(runtime_modifier)


## Template base duration plus the snapshotted STATUS_DURATION bonus.
func get_effective_duration() -> float:
	return template.base_duration + duration_bonus


## Tick damage multiplier from time spent active (linear ramp, capped at the template cap plus the snapshotted bonus).
func get_ramp_multiplier() -> float:
	return 1.0 + minf(elapsed * template.ramp_bonus_per_second, template.ramp_max_bonus + ramp_cap_bonus)


## Most stacks this application can hold. REFRESH has a cap of 1 and STACK uses the template's max_stacks.
## A ticking template adds the snapshotted STATUS_STACK_BONUS (rounded, never negative); other templates ignore it.
func get_stack_cap() -> int:
	var cap := 1
	if template.stacking == StatusEffect.StackingPolicy.STACK:
		cap = maxi(template.max_stacks, 1)
	if template.tick_interval > 0.0:
		cap += maxi(roundi(stack_cap_bonus), 0)
	return cap


## Damage dealt by one tick: DOT_DAMAGE (per second) * ramp * interval * stacks. Never crits.
func get_tick_damage() -> float:
	return dot_damage * get_ramp_multiplier() * template.tick_interval * stacks


## Rewrites runtime modifier values from the template for the current stack count.
func refresh_modifier_values() -> void:
	for i in range(runtime_modifiers.size()):
		var template_value: float = template.stat_modifiers[i].value
		if runtime_modifiers[i].type == StatModifier.Type.MULTIPLICATIVE:
			runtime_modifiers[i].value = pow(1.0 + template_value, stacks) - 1.0
		else:
			runtime_modifiers[i].value = template_value * stacks
