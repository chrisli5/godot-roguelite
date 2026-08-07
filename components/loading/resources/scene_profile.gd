class_name SceneProfile
extends Resource

enum SceneCategory { GAMEPLAY_LEVEL, USER_INTERFACE, CUTSCENE }

@export_group("Core Identification")
## The lookup handle string used by scripts (e.g. "main_menu", "credits", "level_01")
@export var scene_id: String = ""
@export var display_name: String = ""
@export var category: SceneCategory = SceneCategory.GAMEPLAY_LEVEL

@export_group("Asset Linking")
@export_file("*.tscn") var scene_file_path: String = ""

@export_group("Contextual Configurations")
@export var ambient_bgm: AudioStream
## Only evaluated if category is GAMEPLAY_LEVEL
@export var regional_blueprint_profiles: Array[UpgradeBlueprintProfile] = []
