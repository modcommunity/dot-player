@tool
extends EditorPlugin

## Editor entry point for dot-player. Registers inspector types only.
##
## No autoloads: a listen server holds an authoritative roster and the client half of
## the same process holds a mirror, which is precisely the pair an autoload forbids.

const _ICON := "res://addons/dot_player/icon_placeholder.svg"

const _TYPES := [
	["DotPlayerRoster", "Node", "res://addons/dot_player/runtime/dot_player_roster.gd"],
	["DotPlayer", "Node", "res://addons/dot_player/nodes/dot_player.gd"],
	["DotPlayerComponent", "Node", "res://addons/dot_player/nodes/dot_player_component.gd"],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
