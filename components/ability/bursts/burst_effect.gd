class_name BurstEffect
extends Node2D
## Optional base class for a burst's effect scene when the effect needs the cast's numbers (for example a
## lingering zone that applies the cast's Burn).


## Called before the node enters the tree, with a copy of the cast's payload (the effect owns the copy).
## The copy is already marked is_burst with no impact bursts and no crit, so hitting enemies with it can
## never start another burst. Statuses and their snapshots are kept. The node has no position yet.
func configure(_source_payload: CombatPayload) -> void:
	pass
