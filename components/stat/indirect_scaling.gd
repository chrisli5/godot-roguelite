class_name IndirectScaling
extends RefCounted
## Cast-time damage scale from the active indirect effects of a slot. Each effect converts one of the slot's own direct
## stats into a damage bonus: Frost (cooldown shaved), Wind (SPEED_BONUS), Lightning (CRIT_CHANCE), Earth (REACH_BONUS).
## The scale multiplies a cast's hit damage and DoT snapshot once, in CombatCalculations.generate_hit_payload.

## The most the summed indirect bonuses can add (damage_scale is at most 1.0 + this).
const TOTAL_BONUS_CAP: float = 0.5


## The level gate every indirect effect uses: active only when the card's level in the slot reaches the unlock level.
static func is_active(effect: IndirectEffectDefinition, card_level: int) -> bool:
	return effect != null and effect.kind != IndirectEffectDefinition.Kind.NONE and is_unlocked(card_level, effect.unlock_level)


## The one level comparison: a card's level in a slot has reached an unlock level. Burst cards use it too.
static func is_unlocked(card_level: int, unlock_level: int) -> bool:
	return card_level >= unlock_level


## 1.0 + the summed bonuses of `effects` (already gated), clamped to TOTAL_BONUS_CAP. 1.0 for no effects or invalid stats.
static func damage_scale(effects: Array[IndirectEffectDefinition], stats: StatsContainer) -> float:
	if not is_instance_valid(stats) or effects.is_empty():
		return 1.0
	var total := 0.0
	for effect in effects:
		total += bonus_of(effect, stats)
	return 1.0 + clampf(total, 0.0, TOTAL_BONUS_CAP)


## One effect's bonus, never negative.
static func bonus_of(effect: IndirectEffectDefinition, stats: StatsContainer) -> float:
	match effect.kind:
		IndirectEffectDefinition.Kind.COOLDOWN_DAMAGE:
			var cooldown_stat := stats.stats.get(Stat.Type.COOLDOWN, null) as Stat
			if cooldown_stat == null or effect.step_seconds <= 0.0:
				return 0.0
			var effective := maxf(stats.get_final_stat_value(Stat.Type.COOLDOWN), effect.cooldown_floor)
			var shaved := maxf(cooldown_stat.base_value - effective, 0.0)
			return shaved / effect.step_seconds * effect.per_step
		IndirectEffectDefinition.Kind.SPEED_DAMAGE:
			return effect.speed_ratio * maxf(stats.get_final_stat_value(Stat.Type.SPEED_BONUS), 0.0)
		IndirectEffectDefinition.Kind.CRIT_DAMAGE:
			return effect.crit_ratio * maxf(stats.get_final_stat_value(Stat.Type.CRIT_CHANCE), 0.0)
		IndirectEffectDefinition.Kind.REACH_DAMAGE:
			return effect.reach_ratio * maxf(stats.get_final_stat_value(Stat.Type.REACH_BONUS), 0.0)
	return 0.0
