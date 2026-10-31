class_name LevelGate
extends RefCounted


## The one level comparison: a card's level in a slot has reached an unlock level. Used by burst gating.
static func is_unlocked(card_level: int, unlock_level: int) -> bool:
	return card_level >= unlock_level
