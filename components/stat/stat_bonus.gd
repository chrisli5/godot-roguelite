class_name StatBonus
extends RefCounted
## The one place Earth's and Wind's bonus stats are applied. A geometry reads every reach and
## speed stat it declares through here: value * (1 + bonus). QUERY_RADIUS is never read through it.


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
