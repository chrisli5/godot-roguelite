class_name StatusEffectInstance
extends RefCounted
## Runtime state for ONE application of a StatusEffect template on ONE entity.

var template: StatusEffect
var instance_id: int = 0
var time_remaining: float = 0.0
var elapsed: float = 0.0
var tick_accumulator: float = 0.0

## Magnitudes snapshotted from the source's stats when the hit was generated.
var dot_damage: float = 0.0
var duration_bonus: float = 0.0
var ramp_cap_bonus: float = 0.0
## Applied magnitude bonus (clamped to the template cap). Only magnitude-scaling templates ever set it.
var magnitude_bonus: float = 0.0

## Build-up meter state (only used by templates with buildup_per_application > 0).
var buildup: float = 0.0
var is_frozen: bool = false
var frozen_time_left: float = 0.0
## While above 0 the meter cannot build (it stays 0).
var immunity_time_left: float = 0.0

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


## Sets the magnitude bonus (clamped to 0..template.max_magnitude_bonus) and rewrites each runtime modifier's value
## from the matching TEMPLATE modifier's value * (1 + bonus). Does nothing unless the template scales its magnitude.
## The template is never mutated. While Frozen the bonus is stored but the modifier values stay at the frozen value;
## leave_frozen restores them with it.
func set_magnitude_bonus(bonus: float) -> void:
	if not template.magnitude_scales:
		return
	magnitude_bonus = clampf(bonus, 0.0, template.max_magnitude_bonus)
	if not is_frozen:
		_restore_modifier_values()


## Adds `amount` to the meter. Does nothing while Frozen, during the post-freeze immunity, or for a template with no
## meter. Returns true when this addition enters the Frozen phase.
func add_buildup(amount: float) -> bool:
	if template.buildup_per_application <= 0.0 or is_frozen or immunity_time_left > 0.0:
		return false
	buildup += amount
	if buildup >= template.buildup_threshold:
		enter_frozen()
		return true
	return false


## Drains the meter and counts down the Frozen and immunity timers. Returns true when the Frozen phase ended this step.
func advance_buildup(delta: float) -> bool:
	if template.buildup_per_application <= 0.0:
		return false
	if is_frozen:
		frozen_time_left -= delta
		if frozen_time_left <= 0.0:
			leave_frozen()
			return true
		return false
	immunity_time_left = maxf(immunity_time_left - delta, 0.0)
	buildup = maxf(buildup - template.buildup_drain_per_second * delta, 0.0)
	return false


## Starts the Frozen phase: every runtime modifier takes template.frozen_modifier_value.
func enter_frozen() -> void:
	is_frozen = true
	frozen_time_left = template.freeze_duration
	for runtime_modifier in runtime_modifiers:
		runtime_modifier.value = template.frozen_modifier_value


## Ends the Frozen phase: modifiers return to their (magnitude scaled) template values, the meter resets, immunity starts,
## and the status keeps running for at least its effective duration.
func leave_frozen() -> void:
	is_frozen = false
	frozen_time_left = 0.0
	buildup = 0.0
	immunity_time_left = template.freeze_immunity
	_restore_modifier_values()
	time_remaining = maxf(time_remaining, get_effective_duration())


## Writes each runtime modifier's value from the matching TEMPLATE modifier's value * (1 + magnitude_bonus).
func _restore_modifier_values() -> void:
	var runtime_index := 0
	for template_modifier in template.stat_modifiers:
		if not is_instance_valid(template_modifier):
			continue
		runtime_modifiers[runtime_index].value = template_modifier.value * (1.0 + magnitude_bonus)
		runtime_index += 1


## Template base duration plus the snapshotted STATUS_DURATION bonus.
func get_effective_duration() -> float:
	return template.base_duration + duration_bonus


## Tick damage multiplier from time spent active (linear ramp, capped at the template cap plus the snapshotted bonus).
func get_ramp_multiplier() -> float:
	return 1.0 + minf(elapsed * template.ramp_bonus_per_second, template.ramp_max_bonus + ramp_cap_bonus)


## Damage dealt by one tick: DOT_DAMAGE (per second) * ramp * interval. Never crits.
func get_tick_damage() -> float:
	return dot_damage * get_ramp_multiplier() * template.tick_interval
