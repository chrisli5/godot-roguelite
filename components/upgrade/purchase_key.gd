class_name PurchaseKey
extends RefCounted
## The one place that builds and parses slot-specific purchase keys in the run ledger.
## A slot-specific purchase (an infusion or Overclock) is stored as "<upgrade_id>::slot_<n>".
## The stored format is part of save and golden compatibility: do not change it here.

const SEPARATOR := "::slot_"


## The ledger key for `upgrade_id` bought for hotbar `slot_index`.
static func make(upgrade_id: String, slot_index: int) -> String:
	return "%s%s%d" % [upgrade_id, SEPARATOR, slot_index]


## Splits a slot-specific key into {"upgrade_id": String, "slot": int}.
## Returns an empty Dictionary when `key` is not a slot-specific key.
static func parse(key: String) -> Dictionary:
	var split_at := key.rfind(SEPARATOR)
	if split_at <= 0:
		return {}
	var slot_text := key.substr(split_at + SEPARATOR.length())
	if not slot_text.is_valid_int():
		return {}
	return {"upgrade_id": key.substr(0, split_at), "slot": slot_text.to_int()}
