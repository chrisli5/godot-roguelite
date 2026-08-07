class_name MenuActionType
extends Resource

enum ActionIntent { LOAD_SCENE, TOGGLE_OPTIONS_PANEL, QUIT_GAME }

@export_group("Behavior Mode")
## Select what happens when this menu item button is clicked
@export var intent: ActionIntent = ActionIntent.LOAD_SCENE

@export_group("Target Scene")
## Used ONLY if intent is set to LOAD_SCENE. 
## The exact scene identifier key matching your SceneDatabase (e.g. "level_01")
@export var target_scene_id: String = ""
