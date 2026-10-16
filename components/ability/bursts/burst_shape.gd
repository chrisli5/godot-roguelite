@abstract
class_name BurstShape
extends Resource
## Decides where an impact burst reaches. A shape only finds targets; it never applies damage.
## All burst rules (damage, crit, statuses, recursion) live in ImpactBurst.


## Hurtboxes a burst centered at `origin` would hit, excluding the hurtbox with `exclude_instance_id`
## (the primary target). The array may contain the same hurtbox more than once.
@abstract
func find_targets(origin: Vector2, stats: StatsContainer, space_state: PhysicsDirectSpaceState2D, exclude_instance_id: int) -> Array[HurtboxComponent]
