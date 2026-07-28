extends GutTest

const StatClass = preload("res://components/stat_system/resources/stat.gd")
const StatModifierClass = preload("res://components/stat_system/resources/stat_modifier.gd")
const StatsContainerClass = preload("res://components/stat_system/stats_container.gd")
const StatsProfileClass = preload("res://components/stat_system/resources/stats_profile.gd")
const AbilityDataClass = preload("res://components/ability_system/resources/ability_data.gd")

var container: StatsContainer

# Runs automatically before every individual test method
func before_each() -> void:
	# Use GUT's memory management to automatically clear nodes and avoid leaks
	container = autofree(StatsContainerClass.new())

func test_ability_data_resource_binding() -> void:
	var mock_profile = autofree(StatsProfileClass.new())
	var ability_data = autofree(AbilityDataClass.new())
	
	# Create a dummy packed scene or load a placeholder to test reference retention
	var mock_scene = PackedScene.new()
	
	ability_data.ability_scene = mock_scene
	ability_data.stats_profile = mock_profile
	
	assert_not_null(ability_data.ability_scene, "AbilityData should accurately hold a PackedScene reference.")
	assert_not_null(ability_data.stats_profile, "AbilityData should safely bind a custom StatsProfile asset.")
	assert_eq(ability_data.stats_profile, mock_profile, "The assigned profile instance must match the stored reference exactly.")
# --- STAT RESOURCE TESTS ---

func test_flat_modifier_calculation() -> void:
	var stat = autofree(StatClass.new())
	stat.type = StatClass.Type.ATTACK
	stat.base_value = 100.0
	
	var mod = autofree(StatModifierClass.new())
	mod.id = "sword_buff"
	mod.type = StatModifierClass.Type.FLAT
	mod.value = 15.0
	
	stat.add_modifier(mod)
	assert_eq(stat.current_value, 115.0, "Flat modifier should be added to base value.")

	stat.remove_modifier("sword_buff")
	assert_eq(stat.current_value, 100.0, "Flat modifier should be removed from base value.")


func test_percent_modifier_calculation() -> void:
	var stat = autofree(StatClass.new())
	stat.type = StatClass.Type.SPEED
	stat.base_value = 200.0
	
	var mod = autofree(StatModifierClass.new())
	mod.id = "haste_buff"
	mod.type = StatModifierClass.Type.PERCENT
	mod.value = 0.5 # +50%
	
	stat.add_modifier(mod)
	assert_eq(stat.current_value, 300.0, "Percent modifier should multiply flat totals properly.")

	stat.remove_modifier("haste_buff")
	assert_eq(stat.current_value, 200.0, "Percent modifier should be removed from value.")


func test_flat_and_percent_modifier_calculation() -> void:
	var stat = autofree(StatClass.new())
	stat.type = StatClass.Type.ATTACK
	stat.base_value = 100.0
	
	var flat_mod = autofree(StatModifierClass.new())
	flat_mod.id = "sword_buff"
	flat_mod.type = StatModifierClass.Type.FLAT
	flat_mod.value = 20.0
	
	var flat_mod_b = autofree(StatModifierClass.new())
	flat_mod_b.id = "food_buff"
	flat_mod_b.type = StatModifierClass.Type.FLAT
	flat_mod_b.value = 10.0
	
	var percent_mod = autofree(StatModifierClass.new())
	percent_mod.id = "haste_buff"
	percent_mod.type = StatModifierClass.Type.PERCENT
	percent_mod.value = 0.5 # +50%
	
	var percent_mod_b = autofree(StatModifierClass.new())
	percent_mod_b.id = "potion_buff"
	percent_mod_b.type = StatModifierClass.Type.PERCENT
	percent_mod_b.value = 0.3 # +30%
	
	stat.add_modifier(flat_mod)
	stat.add_modifier(flat_mod_b)
	stat.add_modifier(percent_mod)
	stat.add_modifier(percent_mod_b)
	assert_eq(stat.current_value, 234.0, "Flat and percent modifier should be added to base value.")

	stat.remove_modifier(flat_mod.id)
	stat.remove_modifier(percent_mod.id)
	assert_eq(stat.current_value, 143.0, "Flat and percent modifier should be removed from base value.")


func test_max_value_clamping() -> void:
	var stat = autofree(StatClass.new())
	stat.type = StatClass.Type.MAX_HEALTH
	stat.base_value = 100.0
	stat.max_value = 150.0
	
	var massive_mod = autofree(StatModifierClass.new())
	massive_mod.id = "god_mode"
	massive_mod.type = StatModifierClass.Type.FLAT
	massive_mod.value = 999.0
	
	stat.add_modifier(massive_mod)
	assert_eq(stat.current_value, 150.0, "Final value must be capped at max_value.")

# --- CONTAINER & SIGNAL TESTS ---

func test_container_initialization_from_profile() -> void:
	var profile = autofree(StatsProfileClass.new())
	var health_stat = StatClass.new() # Will be duplicated by container, autofree handles via tree
	health_stat.type = StatClass.Type.MAX_HEALTH
	health_stat.base_value = 500.0
	profile.default_stats.append(health_stat)
	
	# Execute container init
	container.initialize_profile(profile)
	
	assert_true(container.stats.has(StatClass.Type.MAX_HEALTH), "Container should index stat by Type.")
	assert_eq(container.get_stat_value(StatClass.Type.MAX_HEALTH), 500.0, "Container values should match profile data.")

func test_stat_updated_signal_emission() -> void:
	var profile = autofree(StatsProfileClass.new())
	var attack_stat = StatClass.new()
	attack_stat.type = StatClass.Type.ATTACK
	attack_stat.base_value = 10.0
	profile.default_stats.append(attack_stat)
	
	container.initialize_profile(profile)
	
	# Watch the container node for signal emissions
	watch_signals(container)
	
	var mod = autofree(StatModifierClass.new())
	mod.id = "potion"
	mod.type = StatModifierClass.Type.FLAT
	mod.value = 5.0
	
	container.add_modifier(StatClass.Type.ATTACK, mod)
	
	# Verify that the container emitted its signal forwarding the change
	assert_signal_emitted(container, "stat_updated", "Modifier application should trigger container update signal.")
	assert_signal_emitted_with_parameters(container, "stat_updated", [StatClass.Type.ATTACK, 15.0])
