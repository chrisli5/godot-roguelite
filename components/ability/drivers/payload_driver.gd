@abstract
class_name PayloadDriver
extends Node

## Acts upon a transient "hit_payload" object generated during ability execution, injecting it with custom properties defined in this driver.
@abstract
func intercept_payload(payload: CombatPayload) -> void
