class_name CombatPhysics
extends RefCounted
## Physics constants shared by every spatial query that looks for enemies. Defined once; no driver declares its own.

## The physics layer bit mask that enemy hurtboxes sit on.
const ENEMY_HURTBOX_MASK: int = 4

## The most results any one shape query returns; larger crowds are cut off.
const MAX_QUERY_RESULTS: int = 32
