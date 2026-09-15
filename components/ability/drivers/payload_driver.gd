class_name PayloadDriver
extends Node

## Virtual Method: Called by a geometry driver right before damage evaluation resolves.
## The driver acts upon a transient object and does not maintain state.
func intercept_payload(payload: HitPayload) -> void:
	pass
