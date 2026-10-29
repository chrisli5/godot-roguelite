# res://components/collision/hurtbox_component.gd
class_name HurtboxComponent
extends Area2D

signal hit_received(payload: CombatPayload)

var owner_entity: Entity = null
var is_player_hurtbox: bool:
	get:
		return owner_entity is Player


func take_hit(payload: CombatPayload) -> void:
	if not is_instance_valid(payload):
		return

	# Each hit rolls its own crit before bursts qualify and before hit_received, so both see the per-hit flag.
	# The receiving entity's INCOMING_CRIT_BONUS (for example from Shock) raises the chance; a null owner passes null.
	var target_stats: StatsContainer = owner_entity.stats_container if is_instance_valid(owner_entity) else null
	payload = CombatCalculations.resolve_hit_crit(payload, target_stats)
	var refund := CombatCalculations.claim_crit_refund(payload)
	if refund > 0.0:
		payload.cast_events.cooldown_refunded.emit(refund)

	# A burst's own payload (is_burst) never starts another burst. Which bursts qualify is decided
	# before hit_received, so this hit's own statuses cannot satisfy a required target tag.
	if payload.impact_bursts.is_empty() or payload.is_burst:
		hit_received.emit(payload)
		return
	var qualifying := _get_qualifying_bursts(payload)
	hit_received.emit(payload)
	if not qualifying.is_empty():
		_queue_impact_bursts(payload, qualifying)


## The payload's bursts whose trigger and required target tag are satisfied by this hurtbox right now.
func _get_qualifying_bursts(payload: CombatPayload) -> Array[ImpactBurstDefinition]:
	var qualifying: Array[ImpactBurstDefinition] = []
	for definition in payload.impact_bursts:
		if definition == null:
			continue
		if definition.trigger == ImpactBurstDefinition.Trigger.ON_CRIT and not payload.is_critical_hit:
			continue
		if definition.required_target_tag != Tags.Type.NONE:
			var tags: TagComponent = owner_entity.tag_component if is_instance_valid(owner_entity) else null
			if not is_instance_valid(tags) or not tags.has_tag(definition.required_target_tag):
				continue
		# Only a qualifying burst spends the cast's budget; a null budget means unlimited.
		if payload.cast_budget != null and not payload.cast_budget.try_spend(definition.get_instance_id(), definition.max_per_cast):
			continue
		qualifying.append(definition)
	return qualifying


## Captures where this hit landed and queues the payload's qualifying bursts for one frame later.
## take_hit can run inside a physics callback, where spatial queries may not be allowed, so the burst
## runs deferred. Only the position and instance id are kept; the enemy itself is never referenced.
func _queue_impact_bursts(payload: CombatPayload, qualifying: Array[ImpactBurstDefinition]) -> void:
	var origin := global_position
	var own_instance_id := get_instance_id()
	var world := get_world_2d()
	for definition in qualifying:
		ImpactBurst.run.call_deferred(definition, payload, origin, own_instance_id, world)
