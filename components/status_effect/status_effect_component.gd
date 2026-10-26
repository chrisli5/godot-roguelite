class_name StatusEffectComponent
extends Node
## Tracks the status effects active on its owner. Knows nothing about sibling components: the
## parent entity listens to these signals and routes modifiers, tick damage and tags.

signal applied(instance: StatusEffectInstance)
## Emitted when an already-active effect is re-applied .
signal refreshed(instance: StatusEffectInstance)
signal ticked(instance: StatusEffectInstance, damage: float)
signal expired(instance: StatusEffectInstance)

## effect_id -> live instance
var _active_effects: Dictionary[String, StatusEffectInstance] = {}
var _next_instance_id: int = 1


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	# Iterate a copy: a tick can kill the owner, which clears effects mid-loop.
	for instance in _active_effects.values():
		if _active_effects.get(instance.template.effect_id) != instance:
			continue
		_advance_instance(instance, delta)


func _exit_tree() -> void:
	# The owner is leaving the tree: drop state without emitting (siblings may already be freed).
	_active_effects.clear()


## Applies `effect` to the owner. `dot_damage` (damage per second), `duration_bonus` (seconds) and
## `ramp_cap_bonus` are the magnitudes snapshotted from the source's DOT_DAMAGE / STATUS_DURATION /
## STATUS_RAMP_CAP stats. An effect whose effective duration is 0 is not applied at all.
## One instance per effect, never stacked. Re-applying a ticking effect: the strongest application wins
## (new dot_damage >= existing adopts the new snapshot as a unit, a weaker one keeps the existing snapshot),
## elapsed is kept and the timer becomes the longer of what is left and the new effective duration.
## Re-applying a non-ticking effect adopts the latest values and resets the timer.
func apply_effect(effect: StatusEffect, dot_damage: float = 0.0, duration_bonus: float = 0.0, ramp_cap_bonus: float = 0.0) -> void:
	if not is_instance_valid(effect) or effect.effect_id.is_empty():
		push_warning("StatusEffectComponent: Invalid status effect passed.")
		return
	if effect.base_duration + duration_bonus <= 0.0:
		return

	var existing: StatusEffectInstance = _active_effects.get(effect.effect_id)
	if existing != null:
		if effect.tick_interval > 0.0:
			var new_duration := effect.base_duration + duration_bonus
			if dot_damage >= existing.dot_damage:
				existing.dot_damage = dot_damage
				existing.duration_bonus = duration_bonus
				existing.ramp_cap_bonus = ramp_cap_bonus
			existing.time_remaining = maxf(existing.time_remaining, new_duration)
		else:
			existing.dot_damage = dot_damage
			existing.duration_bonus = duration_bonus
			existing.ramp_cap_bonus = ramp_cap_bonus
			existing.time_remaining = existing.get_effective_duration()
		refreshed.emit(existing)
		return

	var instance := StatusEffectInstance.new(effect, _next_instance_id)
	_next_instance_id += 1
	instance.dot_damage = dot_damage
	instance.duration_bonus = duration_bonus
	instance.ramp_cap_bonus = ramp_cap_bonus
	instance.time_remaining = instance.get_effective_duration()
	_active_effects[effect.effect_id] = instance
	set_process(true)
	applied.emit(instance)


## Live instances, for the debug inspector and tests. Returns a new array; changing it does not affect the component.
func get_active_instances() -> Array[StatusEffectInstance]:
	var instances: Array[StatusEffectInstance] = []
	instances.assign(_active_effects.values())
	return instances


## Expires every active effect (emitting `expired` for each so listeners can clean up).
func clear_all_effects() -> void:
	for instance in _active_effects.values():
		_expire_instance(instance)


func _advance_instance(instance: StatusEffectInstance, delta: float) -> void:
	instance.elapsed += delta
	instance.time_remaining -= delta

	var interval := instance.template.tick_interval
	if interval > 0.0:
		instance.tick_accumulator += delta
		while instance.tick_accumulator >= interval:
			instance.tick_accumulator -= interval
			var damage := instance.get_tick_damage()
			if damage > 0.0:
				ticked.emit(instance, damage)
			# A tick may have killed the owner and cleared this effect.
			if _active_effects.get(instance.template.effect_id) != instance:
				return

	if instance.time_remaining <= 0.0:
		_expire_instance(instance)


func _expire_instance(instance: StatusEffectInstance) -> void:
	var effect_id := instance.template.effect_id
	if _active_effects.get(effect_id) != instance:
		return
	_active_effects.erase(effect_id)
	if _active_effects.is_empty():
		set_process(false)
	expired.emit(instance)
