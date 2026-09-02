class_name ModifierFactory
extends RefCounted

## Enumerates every architectural system capable of modifying stats.
## If you add a new mechanic (e.g., Relics, Environmental Hazards) later, 
## simply append it to the bottom of this enum.
enum OriginSource {
	LOCAL_UPGRADE,     # Upgrades targeting a specific slot directly
	GLOBAL_UPGRADE,    # Passive cards broadcasting to matching tags
	STATUS_EFFECT,     # Temporary buffs, debuffs, dots
	EQUIPPED_ITEM,     # Weapons, armor, trinkets
	WORLD_ZONE,        # Environmental modifiers (e.g., gravity fields, hexes)
}

## Master function that compiles a standardized, collision-free modifier string.
static func generate_id(
	origin: OriginSource, 
	source_node: Object, 
	target_node: Node, 
	custom_qualifier: String = ""
) -> String:
	
	# 1. Standardize the Origin Namespace string
	var origin_string: String = OriginSource.keys()[origin].to_lower()
	
	# 2. Extract a guaranteed unique ID from the source asset/component instantiating this
	var source_id: String = "0"
	if is_instance_valid(source_node):
		source_id = str(source_node.get_instance_id())
	
	# 3. Extract the unique instance ID of the target receiving the buff (Entity or Ability)
	var target_id: String = "0"
	if is_instance_valid(target_node):
		target_id = str(target_node.get_instance_id())
		
	# 4. Synthesize the deterministic schema block
	var generated_id: String = "%s::%s::%s" % [origin_string, source_id, target_id]
	
	# 5. Append an optional qualifier for micro-targeting (e.g., tracking a sub-component string)
	if not custom_qualifier.is_empty():
		generated_id += "::" + custom_qualifier.to_lower()
		
	return generated_id
