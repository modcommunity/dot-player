class_name DotPlayer
extends Node

## What represents one participant in the world: a container for components.
##
## [b]Deliberately a [Node] and not a [CharacterBody3D].[/b] The moment this extends a
## body it has picked a dimension, and hungario is 2D while arena is 3D; worse, it has
## picked a physics model, and a spectator, a dead player and a player riding in a
## vehicle are all participants with no body of their own at that moment.
##
## So a [DotPlayer] holds the key and finds the body, rather than being one. Everything
## that actually does something — a controller, a character, a weapon, an animation
## driver — is a [DotPlayerComponent] under it, and finds its way back here by walking
## up rather than by a path somebody typed.
##
## [codeblock]
## DotPlayer            player_key = "ada", roster_ref -> the session roster
##   CharacterBody3D    the body, found through body_ref
##   DotFpsController   a component
##   DotPlayerChar      a component
##   DotPlayerAnimDriver a component
## [/codeblock]

const CHANNEL := "player"

## The group every player node joins, so a game can find them all without a registry.
const GROUP := &"dot_players"

## Fired once the key and the roster are both set and the record exists.
##
## [b]Not [code]_ready[/code].[/b] A player node instanced by a spawner has its key
## assigned on the line after [code]add_child[/code], so a component that read the key in
## [code]_ready[/code] would read an empty one — and then quietly do nothing for the rest
## of the round.
signal bound(key: String)

## Fired when the key changes, including from empty to set.
signal key_changed(from: String, to: String)

## Fired when this player's record says they entered or left the world.
signal alive_changed(alive: bool)

## Which participant this node is.
##
## Assigning it re-binds: the group membership, the roster subscription and every
## component are updated. Assignable at runtime because a pooled player node is reused
## for whoever spawns next, and destroying and rebuilding one per respawn is a scene
## rebuild per death.
@export var player_key: String = "":
	set(value):
		if value == player_key:
			return

		var old := player_key
		player_key = value
		_rebind()
		key_changed.emit(old, value)

## Where the session's roster is. Defaults to the registered service.
@export var roster_ref: DotNodeRef = null

## Where this player's physics body is, if they have one.
##
## Optional: a spectator has none, and a component that needs one should say so rather
## than assume. Defaults to the first child that is a collision object.
@export var body_ref: DotNodeRef = null

## Whether this node represents the person at this keyboard.
##
## What a controller reads to decide whether to sample input, and what a camera reads to
## decide whether to become current. Set by whoever spawns the node; nothing here can
## work it out, because a listen server's host player and a remote player are the same
## class in the same tree.
@export var is_local: bool = false

var _roster: DotPlayerRoster = null
var _body: Node = null
var _bound: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	_rebind()


func _exit_tree() -> void:
	_disconnect_roster()


# --- Binding ----------------------------------------------------------------

## Re-resolves the roster and the body. Called on any key change, and callable by hand.
func rebind() -> void:
	_rebind()


func _rebind() -> void:
	if not is_inside_tree():
		return

	_regroup()
	_resolve_roster()
	_body = null
	_bound = false

	if player_key == "":
		return

	if _roster != null and not _roster.has_player(player_key):
		# Not an error. A client's mirror may not have the row yet — the node can arrive
		# before the roster update that explains it — so this is retried whenever the
		# roster changes rather than warned about once and forgotten.
		DotLog.debug(CHANNEL, "no roster row yet", {"key": player_key})
		return

	_bound = true
	bound.emit(player_key)


## A per-key group, so one player can be found without scanning.
##
## [code]dot_player_ada[/code] rather than a registry entry, because a registry name is
## global to the process and two servers in one editor session would collide on it.
func _regroup() -> void:
	for group in get_groups():
		if String(group).begins_with("dot_player_"):
			remove_from_group(group)

	if player_key != "":
		add_to_group(StringName("dot_player_%s" % player_key))


func _resolve_roster() -> void:
	var wanted: DotPlayerRoster = null

	if roster_ref != null:
		wanted = roster_ref.resolve_or_null(self, CHANNEL) as DotPlayerRoster
	else:
		wanted = DotRegistry.get_service(DotPlayerRoster.SERVICE) as DotPlayerRoster

	if wanted == _roster:
		return

	_disconnect_roster()
	_roster = wanted

	if _roster != null:
		_roster.alive_changed.connect(_on_roster_alive_changed)
		_roster.joined.connect(_on_roster_joined)


func _disconnect_roster() -> void:
	if _roster == null:
		return

	if _roster.alive_changed.is_connected(_on_roster_alive_changed):
		_roster.alive_changed.disconnect(_on_roster_alive_changed)

	if _roster.joined.is_connected(_on_roster_joined):
		_roster.joined.disconnect(_on_roster_joined)

	_roster = null


func _on_roster_alive_changed(key: String, alive: bool) -> void:
	if key == player_key:
		alive_changed.emit(alive)


func _on_roster_joined(record: DotPlayerRecord) -> void:
	# The retry named in _rebind: the node arrived before its row did.
	if not _bound and record.key == player_key:
		_bound = true
		bound.emit(player_key)


# --- Reading ----------------------------------------------------------------

func roster() -> DotPlayerRoster:
	if _roster == null:
		_resolve_roster()

	return _roster


## This player's row, or null.
func record() -> DotPlayerRecord:
	var r := roster()
	return r.get_record(player_key) if r != null else null


func is_bound() -> bool:
	return _bound


func team() -> StringName:
	var rec := record()
	return rec.team if rec != null else &""


func player_class() -> StringName:
	var rec := record()
	return rec.player_class if rec != null else &""


func display_name() -> String:
	var rec := record()
	return rec.display_name if rec != null else player_key


func is_alive() -> bool:
	var rec := record()
	return rec.alive if rec != null else false


## The team, as [DotSpawnArea3D] and friends ask for it by duck typing.
##
## Named for the caller rather than for this class: dot-spawn calls
## [code]spawn_team[/code] on whatever body entered an area, and having the player node
## answer it means a game does not have to write a two-line adapter on every body.
func spawn_team() -> StringName:
	return team()


## The physics body, if this player has one.
func body() -> Node:
	if _body != null and is_instance_valid(_body):
		return _body

	if body_ref != null:
		_body = body_ref.resolve_or_null(self, CHANNEL)
	else:
		for child in get_children():
			if child is CollisionObject2D or child is CollisionObject3D:
				_body = child
				break

	return _body


## Where this player is, as a 3D point. Zero when they have no body.
##
## One accessor for both dimensions, with Z unused in 2D, because every consumer —
## dot-spawn's danger scoring, dot-spectate's camera, a HUD's compass — otherwise needs
## its own branch and one of them gets it wrong.
func world_position() -> Vector3:
	var b := body()

	if b is Node3D:
		return (b as Node3D).global_position

	if b is Node2D:
		var p := (b as Node2D).global_position
		return Vector3(p.x, p.y, 0.0)

	# No fallback to this node's own transform: a DotPlayer is a plain Node by design
	# (see the class documentation), so it has no position of its own to fall back to,
	# and a caller reading zero for a player with no body is reading the truth.
	return Vector3.ZERO


# --- Components -------------------------------------------------------------

## Every [DotPlayerComponent] under this node, in tree order.
func components() -> Array[DotPlayerComponent]:
	var out: Array[DotPlayerComponent] = []
	_gather_components(self, out)
	return out


## The first component whose class matches [param type_name], or null.
##
## By name rather than by type so that dot-player does not have to import every addon
## that might supply one — which is the whole reason this is the base package and they
## are not.
func component(type_name: StringName) -> DotPlayerComponent:
	for c in components():
		if c.is_class(String(type_name)):
			return c

		var script := c.get_script() as Script

		while script != null:
			if script.get_global_name() == type_name:
				return c
			script = script.get_base_script()

	return null


func has_component(type_name: StringName) -> bool:
	return component(type_name) != null


func _gather_components(node: Node, out: Array[DotPlayerComponent]) -> void:
	for child in node.get_children():
		if child is DotPlayerComponent:
			out.append(child as DotPlayerComponent)

		# Not descending past a nested DotPlayer: a player node inside another one is a
		# vehicle passenger or a preview, and its components are not this player's.
		if not (child is DotPlayer):
			_gather_components(child, out)


# --- Finding ----------------------------------------------------------------

## The [DotPlayer] a node belongs to, by walking up. Null for a node outside one.
static func of(node: Node) -> DotPlayer:
	var at := node

	while at != null:
		if at is DotPlayer:
			return at as DotPlayer
		at = at.get_parent()

	return null


## Every player node in the tree, by group.
static func all(tree: SceneTree) -> Array[DotPlayer]:
	var out: Array[DotPlayer] = []

	if tree == null:
		return out

	for node in tree.get_nodes_in_group(GROUP):
		if node is DotPlayer:
			out.append(node as DotPlayer)

	return out


## The player node for one key, or null.
static func find(tree: SceneTree, key: String) -> DotPlayer:
	if tree == null or key == "":
		return null

	for node in tree.get_nodes_in_group(StringName("dot_player_%s" % key)):
		if node is DotPlayer:
			return node as DotPlayer

	return null


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var rec := record()

	out.append("player %s%s%s" % [
		player_key if player_key != "" else "<unbound>",
		" (local)" if is_local else "",
		"" if _bound else " — no roster row",
	])

	if rec != null:
		out.append("  " + rec.describe())

	for c in components():
		out.append("  component: %s" % c.component_name())

	return out


func describe() -> String:
	return "DotPlayer(%s)" % (player_key if player_key != "" else "<unbound>")
