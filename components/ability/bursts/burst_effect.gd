class_name BurstEffect
extends Node2D
## Optional base class for a burst's effect scene when the effect needs the cast's numbers (for example a
## lingering zone that applies the cast's Burn).


## Called before the node enters the tree, with a copy of the cast's payload (the effect owns the copy).
func configure(_source_payload: CombatPayload) -> void:
	pass
