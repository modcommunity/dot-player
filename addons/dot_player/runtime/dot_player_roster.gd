class_name DotPlayerRoster
extends Node

## Who is in the session, authoritatively on one machine and mirrored on the rest.
##
## [b]One roster, and everything else reads it.[/b] Before this existed, a team lived in
## dot-match, a class lived in dot-loadout, an alive flag lived in dot-spectate and a key
## lived in dot-stats — four dictionaries keyed the same way, updated from four places,
## and disagreeing about a player who reconnected. This is the row they all read.
##
## [b]And it is a [Node] with an [member authoritative] flag, not a singleton.[/b] A
## listen server holds the real one and the client half of the same process holds a
## mirror; an autoload could hold only one of them. A mirror decides nothing: every
## mutator on a mirror is refused and says so, because a client that can quietly assign
## itself to a team is a client that will.
##
## [codeblock]
## var roster := DotPlayerRoster.new()
## roster.config = DotPlayerConfig.new()
## add_child(roster)
##
## roster.join("ada", "Ada", peer_id, tick)
## roster.set_team("ada", &"blue")
## roster.set_alive("ada", true)
##
## for record in roster.records():
##     print(record.describe())
## [/codeblock]

const CHANNEL := "player.roster"

## Registry name, so anything can find the session's roster without a scene path.
const SERVICE := &"dot_player_roster"

## Somebody joined for the first time.
signal joined(record: DotPlayerRecord)

## Somebody came back inside the reconnect window, with everything they had.
signal rejoined(record: DotPlayerRecord)

## Somebody's connection dropped. Their seat is held; see [signal removed].
signal disconnected(key: String, tick: int)

## Somebody's record is gone: they left, they were removed, or the window expired.
signal removed(key: String, reason: StringName)

## A field changed. [param field] is the property name, for a HUD that redraws one row.
signal changed(key: String, field: StringName)

## Somebody entered or left the world.
signal alive_changed(key: String, alive: bool)

## Whether this instance decides, or is told.
##
## The server's is true; every mirror's is false, and every mutator on a mirror is
## refused with [constant DotError.CODE_FORBIDDEN].
@export var authoritative: bool = true

@export var config: DotPlayerConfig = null

## Whether to register in [DotRegistry] under [constant SERVICE].
@export var register_service: bool = true

var _records: Dictionary = {}

## Insertion order, so [method keys] is stable across machines.
##
## A [Dictionary]'s order is an implementation detail and two machines iterating one in
## a different order produce scoreboards that disagree about who is first — which reads
## as a sorting bug in the UI rather than as this.
var _order: PackedStringArray = PackedStringArray()


func _ready() -> void:
	if config == null:
		config = DotPlayerConfig.new()

	if register_service and authoritative:
		DotRegistry.register(SERVICE, self)


# --- Membership -------------------------------------------------------------

## Adds somebody, or brings back a held seat.
##
## Returns the [DotPlayerRecord] on success. Refuses a full session with
## [constant DotError.CODE_QUOTA], which a server turns into a connect refusal a client
## can actually display.
func join(key: String, display_name: String = "", peer_id: int = 0, tick: int = 0) -> DotResult:
	if not authoritative:
		return _refuse_mirror("join")

	if key == "":
		return DotResult.fail(DotError.CODE_INVALID, "A player with no key cannot be filed.")

	if _records.has(key):
		var existing: DotPlayerRecord = _records[key]

		if existing.connected():
			return DotResult.fail(
				DotError.CODE_STATE,
				"'%s' is already in the session." % key,
				"A second join for a connected key is a bug in the caller, not a "
				+ "reconnect — a reconnect arrives after a drop."
			)

		# The reconnect path. Everything they had is still here, which is the entire
		# reason a dropped record is held rather than deleted.
		existing.disconnected_tick = -1
		existing.reconnected_tick = tick
		existing.peer_id = peer_id

		if display_name != "":
			existing.display_name = config.clean_name(display_name)

		if not config.restore_on_reconnect:
			existing.team = config.default_team
			existing.player_class = config.default_class
			existing.spawn_count = 0
			existing.death_count = 0

		DotLog.info(CHANNEL, "rejoined", {"key": key, "peer": peer_id})
		rejoined.emit(existing)
		return DotResult.success(existing)

	var full := _capacity_refusal(false)

	if full != null:
		return DotResult.failure(full)

	var record := DotPlayerRecord.make(key, config.clean_name(display_name), peer_id)
	record.joined_tick = tick
	record.reconnected_tick = tick
	record.team = config.default_team
	record.player_class = config.default_class

	_records[key] = record
	_order.append(key)

	DotLog.info(CHANNEL, "joined", {"key": key, "name": record.display_name, "peer": peer_id})
	joined.emit(record)
	return DotResult.success(record)


## Adds a bot. Same record, counted against its own cap.
func join_bot(key: String, display_name: String = "", tick: int = 0) -> DotResult:
	if not authoritative:
		return _refuse_mirror("join_bot")

	var full := _capacity_refusal(true)

	if full != null:
		return DotResult.failure(full)

	var res := join(key, display_name, 0, tick)

	if res.ok:
		(res.value as DotPlayerRecord).bot = true
		changed.emit(key, &"bot")

	return res


## Marks somebody as dropped, holding their seat for the reconnect window.
##
## [b]Not the same as leaving.[/b] A player whose connection hiccups mid-round and comes
## back to an empty scoreboard has, from their side, been punished for their router.
## Zero-second windows collapse this into [method remove] and a lobby wants that.
func note_disconnected(key: String, tick: int = 0) -> DotResult:
	if not authoritative:
		return _refuse_mirror("note_disconnected")

	if not _records.has(key):
		return DotResult.fail(DotError.CODE_INVALID, "No such player: '%s'." % key)

	if config.reconnect_window_ticks() <= 0:
		return remove(key, &"disconnected")

	var record: DotPlayerRecord = _records[key]
	record.disconnected_tick = tick
	record.peer_id = 0
	record.alive = false

	DotLog.info(CHANNEL, "disconnected", {"key": key, "tick": tick})
	disconnected.emit(key, tick)
	alive_changed.emit(key, false)
	return DotResult.success(record)


## Drops a record entirely.
func remove(key: String, reason: StringName = &"left") -> DotResult:
	if not authoritative:
		return _refuse_mirror("remove")

	if not _records.has(key):
		return DotResult.fail(DotError.CODE_INVALID, "No such player: '%s'." % key)

	_records.erase(key)

	var index := _order.find(key)
	if index >= 0:
		_order.remove_at(index)

	DotLog.info(CHANNEL, "removed", {"key": key, "reason": String(reason)})
	removed.emit(key, reason)
	return DotResult.success(null)


## Drops every held seat whose window has expired. Call once a tick, or once a second.
##
## Returns the keys it dropped. Necessary for the same reason
## [code]DotSpawnProtection.advance[/code] is: a window that is only ever checked when
## somebody tries to rejoin is a window that never expires, and the roster grows for the
## whole uptime of the server.
func advance(tick: int) -> PackedStringArray:
	var window := config.reconnect_window_ticks()
	var dropped := PackedStringArray()

	if window <= 0 or not authoritative:
		return dropped

	for key: Variant in _records.keys():
		var record: DotPlayerRecord = _records[key]

		if record.connected():
			continue

		if tick - record.disconnected_tick >= window:
			dropped.append(String(key))

	dropped.sort()

	for key in dropped:
		var _res := remove(key, &"timed_out")

	return dropped


# --- Fields -----------------------------------------------------------------

func set_team(key: String, team: StringName) -> DotResult:
	return _set_field(key, &"team", team)


func set_class(key: String, player_class: StringName) -> DotResult:
	return _set_field(key, &"player_class", player_class)


func set_char(key: String, char_id: StringName) -> DotResult:
	return _set_field(key, &"char_id", char_id)


func set_display_name(key: String, display_name: String) -> DotResult:
	return _set_field(key, &"display_name", config.clean_name(display_name))


func set_meta_value(key: String, field: String, value: Variant) -> DotResult:
	if not authoritative:
		return _refuse_mirror("set_meta_value")

	var record := get_record(key)

	if record == null:
		return DotResult.fail(DotError.CODE_INVALID, "No such player: '%s'." % key)

	if DotValue.same(record.meta.get(field, null), value):
		return DotResult.success(record)

	record.meta[field] = value
	changed.emit(key, StringName(field))
	return DotResult.success(record)


## Marks somebody as in or out of the world, counting spawns and deaths.
##
## The counters are here rather than in the caller because every caller would otherwise
## keep its own, and two of them would disagree about a player who was killed by a
## trigger rather than by a person.
func set_alive(key: String, alive: bool) -> DotResult:
	if not authoritative:
		return _refuse_mirror("set_alive")

	var record := get_record(key)

	if record == null:
		return DotResult.fail(DotError.CODE_INVALID, "No such player: '%s'." % key)

	if record.alive == alive:
		return DotResult.success(record)

	record.alive = alive

	if alive:
		record.spawn_count += 1
	else:
		record.death_count += 1

	alive_changed.emit(key, alive)
	changed.emit(key, &"alive")
	return DotResult.success(record)


# --- Reading ----------------------------------------------------------------

func has_player(key: String) -> bool:
	return _records.has(key)


func get_record(key: String) -> DotPlayerRecord:
	return _records.get(key, null)


## Every key, in join order.
func keys() -> PackedStringArray:
	return _order.duplicate()


func records() -> Array[DotPlayerRecord]:
	var out: Array[DotPlayerRecord] = []

	for key in _order:
		out.append(_records[key])

	return out


func count() -> int:
	return _records.size()


func connected_count() -> int:
	var n := 0

	for record in records():
		if record.connected():
			n += 1

	return n


func bot_count() -> int:
	var n := 0

	for record in records():
		if record.bot:
			n += 1

	return n


func alive_count() -> int:
	var n := 0

	for record in records():
		if record.alive:
			n += 1

	return n


## Everybody on a side, in join order.
func team_keys(team: StringName) -> PackedStringArray:
	var out := PackedStringArray()

	for key in _order:
		if (_records[key] as DotPlayerRecord).team == team:
			out.append(key)

	return out


func alive_keys() -> PackedStringArray:
	var out := PackedStringArray()

	for key in _order:
		if (_records[key] as DotPlayerRecord).alive:
			out.append(key)

	return out


## The key a peer id belongs to, or "".
##
## A linear scan on purpose: a reverse index is a second copy of the truth, and the one
## place it would help — a packet arriving from a peer — is already doing more work than
## this per packet.
func key_of_peer(peer_id: int) -> String:
	if peer_id == 0:
		return ""

	for key in _order:
		if (_records[key] as DotPlayerRecord).peer_id == peer_id:
			return key

	return ""


func is_full() -> bool:
	return _capacity_refusal(false) != null


# --- Mirroring --------------------------------------------------------------

## The whole roster, for a client that just connected.
func to_wire() -> Dictionary:
	var rows: Array = []

	for record in records():
		rows.append(record.to_dict())

	return {"players": rows}


## One row, for a change.
func row_to_wire(key: String) -> Dictionary:
	var record := get_record(key)
	return record.to_dict() if record != null else {}


## Replaces a mirror's contents wholesale.
##
## Refused on an authoritative roster. A server that can be told what its own roster is
## by a packet is a server with no roster at all.
func apply_wire(payload: Dictionary) -> DotResult:
	if authoritative:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN,
			"An authoritative roster is not told what it contains.",
			"Set authoritative = false on the mirror, or stop sending it wire updates."
		)

	var rows: Variant = payload.get("players", [])

	if not (rows is Array):
		return DotResult.fail(DotError.CODE_PARSE, "A roster payload has no player list.")

	_records.clear()
	_order = PackedStringArray()

	for row: Variant in rows as Array:
		if not (row is Dictionary):
			continue

		var record := DotPlayerRecord.from_dict(row as Dictionary)

		if record.key == "":
			continue

		_records[record.key] = record
		_order.append(record.key)

	return DotResult.success(_records.size())


## Applies one changed row to a mirror, adding it if it is new.
func apply_row(row: Dictionary) -> DotResult:
	if authoritative:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "An authoritative roster is not told what it contains."
		)

	var record := DotPlayerRecord.from_dict(row)

	if record.key == "":
		return DotResult.fail(DotError.CODE_PARSE, "A roster row has no key.")

	var existed := _records.has(record.key)
	var was_alive := existed and (_records[record.key] as DotPlayerRecord).alive

	_records[record.key] = record

	if not existed:
		_order.append(record.key)
		joined.emit(record)
	else:
		changed.emit(record.key, &"row")

	if was_alive != record.alive:
		alive_changed.emit(record.key, record.alive)

	return DotResult.success(record)


## Removes a row on a mirror.
func drop_row(key: String) -> DotResult:
	if authoritative:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "An authoritative roster is not told what it contains."
		)

	if not _records.has(key):
		return DotResult.success(null)

	_records.erase(key)

	var index := _order.find(key)
	if index >= 0:
		_order.remove_at(index)

	removed.emit(key, &"mirrored")
	return DotResult.success(null)


func clear() -> void:
	_records.clear()
	_order = PackedStringArray()


# --- Reporting --------------------------------------------------------------

func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("roster: %d players (%d connected, %d bots, %d alive)%s" % [
		count(), connected_count(), bot_count(), alive_count(),
		"" if authoritative else " [mirror]",
	])

	for record in records():
		out.append("  " + record.describe())

	return out


func describe() -> String:
	return "DotPlayerRoster(%d players%s)" % [
		count(), "" if authoritative else ", mirror"
	]


# --- Internals --------------------------------------------------------------

func _set_field(key: String, field: StringName, value: Variant) -> DotResult:
	if not authoritative:
		return _refuse_mirror(String(field))

	var record := get_record(key)

	if record == null:
		return DotResult.fail(DotError.CODE_INVALID, "No such player: '%s'." % key)

	# DotValue rather than ==: the incoming value comes from a console command, a wire
	# message or a menu, so its Variant type is not under this file's control, and == on
	# mismatched types is a runtime error that abandons the expression and leaves the
	# caller with an undefined condition.
	if DotValue.same(record.get(String(field)), value):
		return DotResult.success(record)

	record.set(String(field), value)
	changed.emit(key, field)
	return DotResult.success(record)


func _refuse_mirror(what: String) -> DotResult:
	return DotResult.fail(
		DotError.CODE_FORBIDDEN,
		"A mirrored roster decides nothing; it is told. ('%s')" % what,
		"This instance has authoritative = false. The server's roster is the one that "
		+ "decides, and a client that can quietly assign itself to a team is a client "
		+ "that will."
	)


## Null when there is room, a [DotError] when there is not.
func _capacity_refusal(for_bot: bool) -> DotError:
	if for_bot and config.max_bots > 0 and bot_count() >= config.max_bots:
		return DotError.make(
			DotError.CODE_QUOTA,
			"There is room for %d bots and there are already that many." % config.max_bots
		)

	if config.max_players <= 0:
		return null

	var occupied := 0

	for record in records():
		if record.connected() or config.reserved_seats_count:
			occupied += 1

	if occupied < config.max_players:
		return null

	return DotError.make(
		DotError.CODE_QUOTA,
		"The session is full (%d of %d)." % [occupied, config.max_players],
		"Held seats count towards this by default: freeing a slot the moment a "
		+ "connection hiccups lets a stranger take the place of the player who is "
		+ "reconnecting into it."
	)
