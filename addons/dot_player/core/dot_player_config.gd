@tool
class_name DotPlayerConfig
extends DotConfig

## Every policy about who may be in the session, layered.

@export_group("Capacity")

## How many players the session holds. Zero is unlimited.
@export_range(0, 1024, 1) var max_players: int = 32

## How many of those may be bots.
##
## Counted separately because a server that fills with bots and then refuses a person is
## a server nobody can join, and the fix is a cap rather than a rule about ordering.
@export_range(0, 1024, 1) var max_bots: int = 0

## Whether a held seat counts towards [member max_players].
##
## [b]On.[/b] Freeing the slot the moment a connection hiccups is how a full server
## lets a stranger take the place of the player who is reconnecting into it.
@export var reserved_seats_count: bool = true

@export_group("Reconnecting")

## Seconds a disconnected player's record is held before it is dropped.
##
## Zero drops immediately, which is what a lobby wants and a competitive match does not.
@export_range(0.0, 3600.0, 1.0) var reconnect_window_sec: float = 60.0

## Whether a returning player keeps their score, team and class.
@export var restore_on_reconnect: bool = true

@export_group("Identity")

## Whether two records may share a display name.
##
## Allowed by default. Refusing it means a player is told their name is taken by
## somebody who left ten minutes ago, and impersonation is a moderation problem rather
## than a uniqueness one.
@export var allow_duplicate_names: bool = true

## Longest display name accepted. Longer ones are truncated, not refused.
@export_range(1, 256, 1) var max_name_length: int = 32

## What to call somebody who supplied nothing.
@export var default_name: String = "Player"

@export_group("Defaults")

## The team a new record starts on. Empty means unassigned.
@export var default_team: StringName = &""

## The class a new record starts on.
@export var default_class: StringName = &""

## Ticks per second, for turning the window above into ticks.
@export_range(1, 1000, 1) var tick_rate: int = 60


func env_prefix() -> String:
	return "DOT_PLAYER_"


func cli_prefix() -> String:
	return "player-"


func validate() -> DotResult:
	if max_players > 0 and max_bots > max_players:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"There is room for %d players and up to %d bots, so the server can "
				+ "fill with bots and then refuse everybody."
			) % [max_players, max_bots]
		)

	if max_name_length < 1:
		return DotResult.fail(DotError.CODE_INVALID, "A name of zero characters is not a name.")

	return DotResult.success(null)


func reconnect_window_ticks() -> int:
	return int(round(reconnect_window_sec * float(maxi(1, tick_rate))))


## Trims and defaults a display name. Never refuses one.
##
## Truncation rather than rejection: a player whose name is one character too long
## should get in with a shorter name, not bounce off a server with an error about text
## length. dot-user is where the stricter validation lives, for a session that has
## identity at all.
func clean_name(raw: String) -> String:
	var name := raw.strip_edges()

	if name == "":
		name = default_name

	if name.length() > max_name_length:
		name = name.substr(0, max_name_length).strip_edges()

	return name if name != "" else default_name
