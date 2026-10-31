class_name StatBonus
extends RefCounted
## The one place Earth's, Wind's and Frost's bonus stats are applied. A geometry reads every reach and
## speed stat it declares through here: value * (1 + bonus). QUERY_RADIUS is never read through it.
## An ability reads its cooldown through here: COOLDOWN / (1 + COOLDOWN_BONUS).

## Smallest divisor `cooldown` uses, so a negative COOLDOWN_BONUS can never make the cooldown zero or negative.
const MIN_COOLDOWN_DIVISOR: float = 0.1



## A reach stat (AOE_RADIUS, CHAIN_RADIUS, ORBIT_RADIUS) scaled by REACH_BONUS. 0.0 when `stats` is not a valid instance.
static func reach(stats: StatsContainer, base_stat: Stat.Type) -> float:
	if not is_instance_valid(stats):
		return 0.0
	return stats.get_final_stat_value(base_stat) * (1.0 + stats.get_final_stat_value(Stat.Type.REACH_BONUS))


## A delay in seconds shortened by SPEED_BONUS: seconds / (1 + bonus). `seconds` unchanged when `stats` is not a valid instance.
static func interval(stats: StatsContainer, seconds: float) -> float:
	if not is_instance_valid(stats):
		return seconds
	return seconds / (1.0 + stats.get_final_stat_value(Stat.Type.SPEED_BONUS))


## A speed stat (PROJECTILE_MOVEMENT_SPEED, ORBIT_ROTATION_SPEED) scaled by SPEED_BONUS. 0.0 when `stats` is not a valid instance.
static func speed(stats: StatsContainer, base_stat: Stat.Type) -> float:
	if not is_instance_valid(stats):
		return 0.0
	return stats.get_final_stat_value(base_stat) * (1.0 + stats.get_final_stat_value(Stat.Type.SPEED_BONUS))


## An ability's cooldown in seconds: COOLDOWN / (1 + COOLDOWN_BONUS), divisor kept at or above MIN_COOLDOWN_DIVISOR. 0.0 when `stats` is not a valid instance.
static func cooldown(stats: StatsContainer) -> float:
	if not is_instance_valid(stats):
		return 0.0
	return stats.get_final_stat_value(Stat.Type.COOLDOWN) / maxf(1.0 + stats.get_final_stat_value(Stat.Type.COOLDOWN_BONUS), MIN_COOLDOWN_DIVISOR)
