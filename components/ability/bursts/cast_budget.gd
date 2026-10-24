class_name CastBudget
extends Resource
## Per-cast spend counters, shared by reference by every copy of the cast's CombatPayload.
## It is a Resource (not a plain RefCounted) because Resource.duplicate only copies exported properties,
## and a shallow duplicate keeps a sub-resource shared, which is what makes the cap hold across hits.

## Spend count per key (for bursts: the definition's instance id).
var _counts: Dictionary[int, int] = {}


## Spends one use of `key`. Returns false, changing nothing, when `max_count` > 0 and already reached.
## max_count <= 0 means no cap (the use is still counted).
func try_spend(key: int, max_count: int) -> bool:
	var spent: int = _counts.get(key, 0)
	if max_count > 0 and spent >= max_count:
		return false
	_counts[key] = spent + 1
	return true


## How many times `key` has been spent this cast.
func count_of(key: int) -> int:
	return _counts.get(key, 0)
