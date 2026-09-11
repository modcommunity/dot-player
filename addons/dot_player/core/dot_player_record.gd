class_name DotPlayerRecord
extends RefCounted

## One row in the roster: everything the session knows about one participant.
##
## [b]A record outlives the node, the body, the round and — for a while — the
## connection.[/b] That is the whole reason it exists as a separate thing from
## [DotPlayer]: a player node is destroyed on death, rebuilt on respawn and absent
## entirely on a client that cannot see them, while their score, their side and their
## chosen class have to survive all three.
##
## The fields here are the ones every addon in this family already asks about
## separately. dot-match has a team, dot-loadout has a class, dot-spectate has an alive
## flag, dot-stats has a key. One row, and the rest read it.

## The stable identity. Not the peer id and not the display name.
##
## [b]Both of those change and this must not.[/b] A peer id is reassigned on reconnect
## and a display name is whatever the player typed; a key is what a ban, a statistic and
## a scoreboard row are filed under, and dot-user is where one comes from in a session
## that has identity at all.
var key: String = ""

## What to show. Free text, validated by dot-user rather than here.
var display_name: String = ""

## The multiplayer peer, or 0 for a bot, a local player, or somebody disconnected.
var peer_id: int = 0

## Which side. [code]&""[/code] until assigned, which is not the same as spectator.
var team: StringName = &""

## Which class. Not [code]class[/code]: that is a reserved word.
var player_class: StringName = &""

## Which character they chose, for dot-player-char.
var char_id: StringName = &""

## Whether they are in the world right now.
var alive: bool = false

## Whether the game drives them rather than a person.
var bot: bool = false

## The tick they first joined on. Survives a reconnect; see [member reconnected_tick].
var joined_tick: int = 0

## The tick they most recently reconnected on, or [member joined_tick].
var reconnected_tick: int = 0

## The tick their connection dropped, or -1 while they are connected.
##
## A record with this set is a held seat rather than a departed player, and the
## difference is the difference between "your score is gone" and "welcome back".
var disconnected_tick: int = -1

var spawn_count: int = 0
var death_count: int = 0

## Anything a game wants to carry per player without a parallel dictionary.
var meta: Dictionary = {}


static func make(p_key: String, p_name: String = "", p_peer: int = 0) -> DotPlayerRecord:
	var r := DotPlayerRecord.new()
	r.key = p_key
	r.display_name = p_name if p_name != "" else p_key
	r.peer_id = p_peer
	return r


func connected() -> bool:
	return disconnected_tick < 0


## Whether this record still counts towards a player limit.
##
## A held seat does. Freeing it the moment somebody's connection hiccups is how a full
## server lets a stranger take the slot of the player who is reconnecting into it.
func occupies_a_slot() -> bool:
	return true


func assigned() -> bool:
	return team != &""


## The wire form. Small on purpose: this is sent for every player on every change.
func to_dict() -> Dictionary:
	return {
		"key": key,
		"name": display_name,
		"peer": peer_id,
		"team": String(team),
		"class": String(player_class),
		"char": String(char_id),
		"alive": alive,
		"bot": bot,
		"joined": joined_tick,
		"spawns": spawn_count,
		"deaths": death_count,
		"meta": meta.duplicate(true),
	}


## The reverse. Missing fields keep their defaults rather than failing.
##
## Tolerant on purpose: a client on an older build receiving a field it does not know
## about, or missing one the server has since added, should render a slightly stale
## scoreboard rather than refuse to render one.
static func from_dict(d: Dictionary) -> DotPlayerRecord:
	var r := DotPlayerRecord.new()
	r.key = str(d.get("key", ""))
	r.display_name = str(d.get("name", r.key))
	r.peer_id = int(d.get("peer", 0))
	r.team = StringName(str(d.get("team", "")))
	r.player_class = StringName(str(d.get("class", "")))
	r.char_id = StringName(str(d.get("char", "")))
	r.alive = bool(d.get("alive", false))
	r.bot = bool(d.get("bot", false))
	r.joined_tick = int(d.get("joined", 0))
	r.reconnected_tick = r.joined_tick
	r.spawn_count = int(d.get("spawns", 0))
	r.death_count = int(d.get("deaths", 0))

	var m: Variant = d.get("meta", {})
	r.meta = (m as Dictionary).duplicate(true) if m is Dictionary else {}

	return r


func copy_record() -> DotPlayerRecord:
	return DotPlayerRecord.from_dict(to_dict())


func describe() -> String:
	return "%s (%s)%s%s%s%s" % [
		display_name,
		key,
		"" if team == &"" else " %s" % String(team),
		"" if player_class == &"" else " %s" % String(player_class),
		" alive" if alive else " dead",
		"" if connected() else " [disconnected]",
	]


func _to_string() -> String:
	return "DotPlayerRecord(%s)" % describe()
