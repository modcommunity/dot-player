class_name DotPlayerComponent
extends Node

## The base every other player addon's node extends.
##
## [b]It exists for one reason: so that nothing has to be told where its player is.[/b]
## Before this, a controller had a [code]player_path[/code], a weapon had a
## [code]owner_path[/code] and an animation driver had an exported [NodePath] to a
## character, and all three were set by hand in a scene that a spawner then instanced
## under a different parent. A component walks up instead, finds the [DotPlayer], and
## is told when the key changes.
##
## Subclasses override [method _on_bound] and [method _on_unbound] rather than
## [code]_ready[/code], because [code]_ready[/code] runs before a spawner has assigned
## the key — and a component that read the key in [code]_ready[/code] would read an empty
## one and then do nothing for the rest of the round, silently.

## Not [code]CHANNEL[/code]. Every subclass of this — in this repository and in the
## four addons that extend it — wants a log channel of its own, and a constant that
## shadows a parent's is a parse error rather than an override. Naming the base's after
## the base leaves the obvious name free for the leaf.
const COMPONENT_CHANNEL := "player.component"

## This component's player changed, or arrived. Also emitted on the first bind.
signal player_bound(player: DotPlayer)

## Its player went away: the key was cleared, or the node was reparented out.
signal player_unbound()

## Where the owning [DotPlayer] is.
##
## Left null, the nearest ancestor is used, which is right in every scene this family
## ships. Set it for the unusual case: a HUD element that is a component of a player it
## is not under.
@export var player_ref: DotNodeRef = null

## Whether this component does anything when its player is not the local one.
##
## Off for a sampler, a camera or a view model: a server holding thirty players should
## not be running thirty first-person cameras, and a client should not be sampling the
## keyboard on behalf of somebody else.
@export var local_only: bool = false

var _player: DotPlayer = null


func _ready() -> void:
	_bind()


func _exit_tree() -> void:
	_unbind()


# --- Binding ----------------------------------------------------------------

## The player this belongs to, or null.
func player() -> DotPlayer:
	if _player == null or not is_instance_valid(_player):
		_bind()

	return _player


func is_bound() -> bool:
	return _player != null and is_instance_valid(_player)


## Whether this component should be doing anything at all right now.
##
## The one call every subclass's [code]_process[/code] starts with. Checks the bind and
## the [member local_only] rule in one place, so that thirty players on a server are not
## thirty copies of the same two conditions written slightly differently.
func is_active() -> bool:
	if not is_bound():
		return false

	if local_only and not _player.is_local:
		return false

	return true


## What to call this in a describe line. Overridden rarely; the class name is fine.
func component_name() -> String:
	var script := get_script() as Script

	if script != null and script.get_global_name() != &"":
		return String(script.get_global_name())

	return get_class()


func _bind() -> void:
	if not is_inside_tree():
		return

	var found: DotPlayer = null

	if player_ref != null:
		found = player_ref.resolve_or_null(self, COMPONENT_CHANNEL) as DotPlayer
	else:
		found = DotPlayer.of(get_parent())

	if found == _player:
		return

	_unbind()

	if found == null:
		DotLog.debug(COMPONENT_CHANNEL, "component has no player", {"node": name})
		return

	_player = found
	_player.key_changed.connect(_on_key_changed)
	_player.tree_exiting.connect(_on_player_leaving)

	_on_bound(_player)
	player_bound.emit(_player)


func _unbind() -> void:
	if _player == null:
		return

	if is_instance_valid(_player):
		if _player.key_changed.is_connected(_on_key_changed):
			_player.key_changed.disconnect(_on_key_changed)
		if _player.tree_exiting.is_connected(_on_player_leaving):
			_player.tree_exiting.disconnect(_on_player_leaving)

	var was := _player
	_player = null

	_on_unbound(was)
	player_unbound.emit()


func _on_key_changed(_from: String, _to: String) -> void:
	# The player node is the same; the person it represents is not. A component holding
	# per-player state — ammunition, a cooldown, a camera angle — has to be told, and a
	# pooled node reused for the next spawn is exactly this case.
	_on_bound(_player)
	player_bound.emit(_player)


func _on_player_leaving() -> void:
	_unbind()


# --- For subclasses ---------------------------------------------------------

## Called when this component gains a player, and again when the key changes.
##
## [b]Must be safe to call twice.[/b] A pooled player node reused for the next spawn
## calls it again with the same node and a different key.
func _on_bound(_p: DotPlayer) -> void:
	pass


## Called when it loses one.
func _on_unbound(_p: DotPlayer) -> void:
	pass


## One line, always available.
##
## [b]There is deliberately no [code]describe()[/code] on this base.[/b] The family's
## convention is that anything stateful has one, and it is not uniform about the return
## type — dot-spectate's manager and dot-player-controller's controller both answer a
## [Dictionary], while most answer a [String]. A base class that fixed the type would
## make every one of those subclasses a parse error, reported against the file that
## uses it rather than the file that declares it. [method describe_lines] is the part
## every consumer of this base actually shares.
func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"%s: %s%s" % [
			component_name(),
			_player.player_key if is_bound() else "<unbound>",
			" (local only)" if local_only else "",
		]
	])
