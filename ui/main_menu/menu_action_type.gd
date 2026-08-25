class_name MenuActionType
extends Resource

# Added START_NEW_RUN to separate standalone scenes from procedural runs
enum ActionIntent { LOAD_SCENE, TOGGLE_OPTIONS_PANEL, QUIT_GAME, START_NEW_RUN }

@export_group("Behavior Mode")
@export var intent: ActionIntent = ActionIntent.LOAD_SCENE

@export_group("Target Configurations")
## Used ONLY if intent is set to LOAD_SCENE.
@export var target_scene_id: String = ""

## Used ONLY if intent is set to START_NEW_RUN. 
## Injects the target Act environment rules (e.g. Act 1 Catacombs data card).
@export var act_configuration: ActConfiguration
