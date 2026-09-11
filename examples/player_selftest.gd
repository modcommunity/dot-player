extends Node

## Exercises dot-player with no world, no transport and no game.
##
## The roster is the half worth checking hardest, because it is the half that is wrong
## in a way nobody notices: a reconnect that loses a score, a held seat that lets a
## stranger in, a mirror that can quietly assign itself to a team. The node half is
## checked against a real tree, because binding by walking up is the one thing here that
## cannot be tested as a value.
##
## [codeblock]
## godot --headless --path . res://examples/player_selftest.tscn
## [/codeblock]

const SECTIONS := 8
const CHECKS := 159

const RATE := 64

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-player self-test")
	_line("")

	_test_record()
	_test_config()
	_test_join_and_leave()
	_test_reconnect()
	_test_capacity()
	_test_fields()
	_test_mirror()
	_test_nodes()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


func _roster(cfg: DotPlayerConfig = null) -> DotPlayerRoster:
	var r := DotPlayerRoster.new()
	r.config = cfg if cfg != null else DotPlayerConfig.new()
	r.config.tick_rate = RATE
	r.register_service = false
	add_child(r)
	return r


# --- Records ----------------------------------------------------------------

func _test_record() -> void:
	_section("a record")

	var r := DotPlayerRecord.make("ada", "Ada", 7)
	_check(r.key == "ada", "carries a stable key")
	_check(r.display_name == "Ada", "and a name")
	_check(r.peer_id == 7, "and the peer it arrived on")
	_check(r.connected(), "and starts connected")
	_check(not r.assigned(), "and unassigned, which is not the same as spectator")
	_check(not r.alive, "and out of the world")

	var blank := DotPlayerRecord.make("bob")
	_check(
		blank.display_name == "bob",
		"a record with no name shows its key rather than an empty string, because an "
		+ "empty scoreboard row reads as a bug"
	)

	r.team = &"blue"
	r.player_class = &"medic"
	r.spawn_count = 3
	r.meta = {"ping": 42}

	var wire := r.to_dict()
	var back := DotPlayerRecord.from_dict(wire)
	_check(back.key == "ada" and back.team == &"blue", "a record survives a round trip")
	_check(back.player_class == &"medic", "with its class")
	_check(back.spawn_count == 3, "and its counters")
	_check(int(back.meta.get("ping", 0)) == 42, "and its metadata")

	var partial := DotPlayerRecord.from_dict({"key": "zoe"})
	_check(
		partial.key == "zoe" and partial.team == &"",
		"a payload missing fields keeps defaults — a client on an older build should "
		+ "render a stale scoreboard, not refuse to render one"
	)
	_check(DotPlayerRecord.from_dict({}).key == "", "and an empty one is empty")

	var copy := r.copy_record()
	copy.team = &"red"
	_check(r.team == &"blue", "a copy is a copy")
	copy.meta["ping"] = 1
	_check(int(r.meta.get("ping", 0)) == 42, "including its metadata")

	_check(r.describe().contains("Ada"), "and a record describes itself")


func _test_config() -> void:
	_section("config")

	var c := DotPlayerConfig.new()
	_check(c.validate().ok, "the defaults validate")
	_check(c.reconnect_window_ticks() == 60 * 60, "sixty seconds at 60 Hz is 3600 ticks")
	_check(
		c.reserved_seats_count,
		"and a held seat counts — freeing it the moment a connection hiccups lets a "
		+ "stranger take the place of the player reconnecting into it"
	)

	_check(c.clean_name("  Ada  ") == "Ada", "a name is trimmed")
	_check(c.clean_name("") == "Player", "an empty one gets a default")
	_check(c.clean_name("   ") == "Player", "and so does whitespace")
	_check(
		c.clean_name("x".repeat(500)).length() == c.max_name_length,
		"a long one is truncated rather than refused — bouncing somebody off a server "
		+ "over text length is worse than shortening it"
	)

	var bad := DotPlayerConfig.new()
	bad.max_players = 4
	bad.max_bots = 8
	_check(
		not bad.validate().ok,
		"more bot slots than player slots is refused: the server fills with bots and "
		+ "then refuses everybody"
	)

	_check(c.env_prefix() == "DOT_PLAYER_", "and it layers the family's way")
	_check(
		c.allow_duplicate_names,
		"two people may share a name by default — refusing means telling somebody "
		+ "their name is taken by a player who left ten minutes ago"
	)
	var applied := c.apply_dictionary({"max_players": 12, "default_team": "blue"})
	_check(applied.size() == 2, "taking a dictionary")
	_check(c.max_players == 12 and c.default_team == &"blue", "with both values through")


# --- Membership -------------------------------------------------------------

func _test_join_and_leave() -> void:
	_section("joining and leaving")

	var roster := _roster()
	var events: Array = []
	roster.joined.connect(func(rec: DotPlayerRecord) -> void: events.append(["join", rec.key]))
	roster.removed.connect(func(key: String, why: StringName) -> void:
		events.append(["remove", key, String(why)])
	)

	var res := roster.join("ada", "Ada", 7, 100)
	_check(res.ok, "somebody joins")
	_check((res.value as DotPlayerRecord).joined_tick == 100, "on a tick")
	_check(roster.has_player("ada"), "and is in the roster")
	_check(roster.count() == 1, "which counts them")
	_check(roster.connected_count() == 1, "as connected")
	_check(events.size() == 1, "with a signal")

	_check(not roster.join("ada", "Ada", 8, 101).ok, "joining twice is refused")
	_check(
		roster.join("ada", "Ada", 8, 101).code() == DotError.CODE_STATE,
		"as a state error, because a second join for a connected key is a caller bug "
		+ "rather than a reconnect"
	)
	_check(not roster.join("", "Nobody").ok, "and a player with no key cannot be filed")

	var _b := roster.join_bot("bot_1", "Bot One", 0)
	_check(roster.bot_count() == 1, "a bot joins as a bot")
	_check(roster.get_record("bot_1").bot, "and says so")

	_check(roster.join("zoe", "Zoe", 9, 102).ok, "a third joins")
	_check(
		roster.keys() == PackedStringArray(["ada", "bot_1", "zoe"]),
		"and the keys come back in join order — a dictionary's order is not a promise, "
		+ "and two machines iterating differently produce scoreboards that disagree"
	)

	_check(roster.key_of_peer(9) == "zoe", "a peer id maps back to a key")
	_check(roster.key_of_peer(0) == "", "and zero maps to nobody, not to the first bot")
	_check(roster.key_of_peer(999) == "", "and an unknown peer to nothing")

	_check(roster.remove("zoe").ok, "somebody leaves")
	_check(not roster.has_player("zoe"), "and is gone")
	_check(roster.keys() == PackedStringArray(["ada", "bot_1"]), "out of the order too")
	_check(events.back()[0] == "remove", "with a signal")
	_check(not roster.remove("nobody").ok, "removing nobody is refused")

	_check(roster.describe_lines().size() == 3, "and the roster describes itself")

	# The setting that used to be declared and read by nothing.
	var strict := DotPlayerConfig.new()
	strict.allow_duplicate_names = false
	var unique := _roster(strict)
	var first := unique.join("a", "Ada")
	var second := unique.join("b", "Ada")
	_check(first.ok and second.ok, "a server forbidding duplicates still lets both in")
	_check(
		(second.value as DotPlayerRecord).display_name == "Ada (2)",
		"and disambiguates rather than refusing, which is the answer every chat system "
		+ "reached decades ago"
	)
	_check(
		unique.set_display_name("b", "Ada").ok
		and unique.get_record("b").display_name == "Ada (2)",
		"and renaming yourself to what you already are is not a collision with yourself"
	)
	unique.queue_free()

	roster.clear()
	_check(roster.count() == 0, "and clears")
	roster.queue_free()


func _test_reconnect() -> void:
	_section("reconnecting")

	var roster := _roster()
	var _j := roster.join("ada", "Ada", 7, 0)
	var _t := roster.set_team("ada", &"blue")
	var _a := roster.set_alive("ada", true)

	var rejoins: Array = []
	roster.rejoined.connect(func(rec: DotPlayerRecord) -> void: rejoins.append(rec.key))

	_check(roster.note_disconnected("ada", 1000).ok, "a connection drops")
	_check(roster.has_player("ada"), "and the record is held")
	_check(not roster.get_record("ada").connected(), "marked as disconnected")
	_check(roster.connected_count() == 0, "and not counted as connected")
	_check(not roster.get_record("ada").alive, "and out of the world")
	_check(roster.count() == 1, "but still occupying a seat")

	var back := roster.join("ada", "Ada", 11, 1100)
	_check(back.ok, "and they come back")
	_check(rejoins.size() == 1, "as a rejoin rather than a join")
	_check(
		(back.value as DotPlayerRecord).team == &"blue",
		"with the team they had — a player whose router hiccups mid-round and returns "
		+ "to an empty scoreboard has been punished for their hardware"
	)
	_check((back.value as DotPlayerRecord).peer_id == 11, "on their new peer")
	_check(
		(back.value as DotPlayerRecord).joined_tick == 0,
		"and the original join tick, so 'time in the session' is still true"
	)
	_check((back.value as DotPlayerRecord).reconnected_tick == 1100, "with the return noted")

	# The window expiring.
	var _d := roster.note_disconnected("ada", 2000)
	_check(roster.advance(2100).is_empty(), "nothing expires early")
	var dropped := roster.advance(2000 + roster.config.reconnect_window_ticks())
	_check(
		dropped.size() == 1 and dropped[0] == "ada",
		"and the seat is freed when the window is up — a window only checked when "
		+ "somebody tries to rejoin is a window that never expires"
	)
	_check(not roster.has_player("ada"), "with the record gone")

	# A zero window, which is what a lobby wants.
	var lobby_cfg := DotPlayerConfig.new()
	lobby_cfg.reconnect_window_sec = 0.0
	var lobby := _roster(lobby_cfg)
	var _lj := lobby.join("bob", "Bob", 3, 0)
	var _ld := lobby.note_disconnected("bob", 0)
	_check(
		not lobby.has_player("bob"),
		"a zero-second window drops immediately, which is a lobby's answer and not a "
		+ "competitive match's"
	)

	# Not restoring, for a mode that does not want it.
	var fresh_cfg := DotPlayerConfig.new()
	fresh_cfg.restore_on_reconnect = false
	var fresh := _roster(fresh_cfg)
	var _fj := fresh.join("mel", "Mel", 5, 0)
	var _ft := fresh.set_team("mel", &"red")
	var _fd := fresh.note_disconnected("mel", 10)
	var again := fresh.join("mel", "Mel", 6, 20)
	_check(
		(again.value as DotPlayerRecord).team == &"",
		"and a mode that would rather start people over can say so"
	)

	roster.queue_free()
	lobby.queue_free()
	fresh.queue_free()


func _test_capacity() -> void:
	_section("capacity")

	var cfg := DotPlayerConfig.new()
	cfg.max_players = 3
	cfg.max_bots = 1
	var roster := _roster(cfg)

	_check(roster.join("a").ok, "the first fits")
	_check(roster.join("b").ok, "the second")
	_check(roster.join("c").ok, "the third")
	_check(roster.is_full(), "and the session is now full")

	var refused := roster.join("d")
	_check(not refused.ok, "the fourth is refused")
	_check(
		refused.code() == DotError.CODE_QUOTA,
		"with a quota code a server can turn into a connect refusal somebody can read"
	)

	var _r := roster.remove("c")
	_check(roster.join("bot_1").ok, "a bot fits in the free slot")
	_check(not roster.join_bot("bot_2").ok, "but a second bot exceeds the bot cap")

	# The held seat.
	var _d := roster.note_disconnected("a", 0)
	_check(
		not roster.join("e").ok,
		"a held seat still counts, so a stranger cannot take the slot of somebody "
		+ "reconnecting into it"
	)

	cfg.reserved_seats_count = false
	_check(
		roster.join("e").ok,
		"and a game that would rather free it immediately can say so"
	)

	var unlimited := DotPlayerConfig.new()
	unlimited.max_players = 0
	var open := _roster(unlimited)
	for i in range(50):
		var _oj := open.join("p%d" % i)
	_check(open.count() == 50, "zero means unlimited")
	_check(not open.is_full(), "and is never full")

	roster.queue_free()
	open.queue_free()


func _test_fields() -> void:
	_section("fields")

	var roster := _roster()
	var _j := roster.join("ada", "Ada", 7, 0)

	var changes: Array = []
	roster.changed.connect(func(key: String, field: StringName) -> void:
		changes.append([key, String(field)])
	)
	var alive_events: Array = []
	roster.alive_changed.connect(func(key: String, alive: bool) -> void:
		alive_events.append([key, alive])
	)

	_check(roster.set_team("ada", &"blue").ok, "a team is assigned")
	_check(roster.get_record("ada").team == &"blue", "and lands")
	_check(changes.size() == 1, "with a signal naming the field")
	_check(changes[0][1] == "team", "which it does")

	_check(roster.set_team("ada", &"blue").ok, "setting the same team again succeeds")
	_check(
		changes.size() == 1,
		"and fires nothing, so a HUD that redraws on every change does not redraw "
		+ "thirty rows a tick for a value nobody altered"
	)

	_check(roster.set_class("ada", &"medic").ok, "a class is assigned")
	_check(roster.set_char("ada", &"scout_f").ok, "so is a character")
	_check(roster.set_display_name("ada", "  Ada Lovelace  ").ok, "and a name")
	_check(roster.get_record("ada").display_name == "Ada Lovelace", "trimmed")

	_check(roster.set_alive("ada", true).ok, "somebody enters the world")
	_check(roster.get_record("ada").spawn_count == 1, "which counts a spawn")
	_check(alive_events.size() == 1, "with its own signal")
	var _again := roster.set_alive("ada", true)
	_check(
		roster.get_record("ada").spawn_count == 1,
		"setting it again counts nothing, or two callers reporting one spawn make two"
	)
	var _dead := roster.set_alive("ada", false)
	_check(roster.get_record("ada").death_count == 1, "and leaving counts a death")
	_check(roster.alive_count() == 0, "with nobody alive")

	_check(roster.set_meta_value("ada", "ping", 42).ok, "metadata is settable")
	_check(int(roster.get_record("ada").meta.get("ping", 0)) == 42, "and lands")
	var before := changes.size()
	var _same := roster.set_meta_value("ada", "ping", 42)
	_check(changes.size() == before, "and the same value again fires nothing")
	_check(
		roster.set_meta_value("ada", "ping", "42").ok,
		"a string against a number is a change rather than a runtime error, because "
		+ "DotValue.same is total where == is not"
	)

	_check(not roster.set_team("nobody", &"blue").ok, "an unknown key is refused")

	var _b := roster.join("bob")
	var _bt := roster.set_team("bob", &"blue")
	var _z := roster.join("zoe")
	var _zt := roster.set_team("zoe", &"red")
	_check(roster.team_keys(&"blue") == PackedStringArray(["ada", "bob"]), "a team lists")
	_check(roster.team_keys(&"red") == PackedStringArray(["zoe"]), "and so does the other")
	var _za := roster.set_alive("zoe", true)
	_check(roster.alive_keys() == PackedStringArray(["zoe"]), "and so does the living")

	roster.queue_free()


func _test_mirror() -> void:
	_section("mirroring")

	var server := _roster()
	var _a := server.join("ada", "Ada", 7, 0)
	var _at := server.set_team("ada", &"blue")
	var _b := server.join("bob", "Bob", 8, 0)
	var _ba := server.set_alive("bob", true)

	var client := DotPlayerRoster.new()
	client.authoritative = false
	client.register_service = false
	add_child(client)

	_check(client.apply_wire(server.to_wire()).ok, "a whole roster travels")
	_check(client.count() == 2, "with both rows")
	_check(client.get_record("ada").team == &"blue", "and their teams")
	_check(client.get_record("bob").alive, "and who is alive")
	_check(
		client.keys() == server.keys(),
		"in the same order, because two machines sorting differently produce "
		+ "scoreboards that disagree about who is first"
	)

	_check(
		not client.join("mallory").ok,
		"a mirror decides nothing: a client that can quietly assign itself to a team "
		+ "is a client that will"
	)
	_check(client.join("mallory").code() == DotError.CODE_FORBIDDEN, "and says so")
	_check(not client.set_team("ada", &"red").ok, "nor reassign anybody")
	_check(not client.set_alive("ada", true).ok, "nor resurrect them")
	_check(not client.remove("ada").ok, "nor remove them")
	_check(client.advance(999999).is_empty(), "and expires nothing of its own")

	_check(
		not server.apply_wire({"players": []}).ok,
		"and the authoritative one is not told what it contains, or it has no roster "
		+ "at all"
	)

	var _t := server.set_team("bob", &"red")
	_check(client.apply_row(server.row_to_wire("bob")).ok, "one changed row travels")
	_check(client.get_record("bob").team == &"red", "and lands")

	var _n := server.join("zoe", "Zoe", 9, 0)
	var joined_on_client: Array = []
	client.joined.connect(func(rec: DotPlayerRecord) -> void: joined_on_client.append(rec.key))
	var _row := client.apply_row(server.row_to_wire("zoe"))
	_check(joined_on_client.size() == 1, "a new row arrives as a join on the mirror")

	_check(client.drop_row("zoe").ok, "and a row can be dropped")
	_check(not client.has_player("zoe"), "leaving the mirror in step")
	_check(client.drop_row("nobody").ok, "dropping nothing is not an error")
	_check(not client.apply_row({}).ok, "a row with no key is refused")

	server.queue_free()
	client.queue_free()


# --- Nodes ------------------------------------------------------------------

func _test_nodes() -> void:
	_section("the player node")

	var roster := _roster()
	var _j := roster.join("ada", "Ada", 7, 0)
	var _t := roster.set_team("ada", &"blue")

	var player := DotPlayer.new()
	player.roster_ref = DotNodeRef.of_path(roster.get_path())
	player.is_local = true
	add_child(player)

	var bound_keys: Array = []
	player.bound.connect(func(key: String) -> void: bound_keys.append(key))

	player.player_key = "ada"
	_check(player.is_bound(), "a player node binds once it has a key and a row")
	_check(bound_keys.size() == 1, "with a signal")
	_check(player.team() == &"blue", "and reads its team through the roster")
	_check(player.display_name() == "Ada", "and its name")
	_check(player.is_in_group(DotPlayer.GROUP), "it joins the group of all players")
	_check(
		player.is_in_group(&"dot_player_ada"),
		"and a per-key group, which is how one player is found without a registry name "
		+ "that two servers in one process would collide on"
	)

	_check(DotPlayer.of(player) == player, "a node finds itself")
	_check(DotPlayer.find(get_tree(), "ada") == player, "and is findable by key")
	_check(DotPlayer.find(get_tree(), "nobody") == null, "an unknown key finds nothing")
	_check(DotPlayer.all(get_tree()).size() == 1, "and all() lists it")
	_check(DotPlayer.of(null) == null, "walking up from nothing finds nothing")

	# Rebinding to somebody else, which is what a pooled node does.
	var _z := roster.join("zoe", "Zoe", 8, 0)
	player.player_key = "zoe"
	_check(player.display_name() == "Zoe", "reassigning the key rebinds the node")
	_check(not player.is_in_group(&"dot_player_ada"), "leaving the old key's group")
	_check(player.is_in_group(&"dot_player_zoe"), "and joining the new one")
	player.player_key = "ada"

	# A body.
	var body := CharacterBody3D.new()
	body.position = Vector3(3, 0, 4)
	player.add_child(body)
	_check(player.body() == body, "a player finds its body without being told which")
	_check(
		player.world_position().is_equal_approx(Vector3(3, 0, 4)),
		"and reports one position for both dimensions, so nothing downstream branches"
	)

	# Components.
	var component := DotPlayerComponent.new()
	player.add_child(component)
	_check(component.is_bound(), "a component binds by walking up")
	_check(component.player() == player, "to the right player")
	_check(component.is_active(), "and is active")
	_check(player.components().size() == 1, "the player lists it")
	_check(
		player.component(&"DotPlayerComponent") == component,
		"and finds it by class name, which is how dot-player avoids importing every "
		+ "addon that might supply one"
	)
	_check(player.component(&"NotAThing") == null, "an unknown class finds nothing")
	_check(player.has_component(&"DotPlayerComponent"), "and has_component agrees")

	var rebinds: Array = []
	component.player_bound.connect(func(_p: DotPlayer) -> void: rebinds.append(1))
	player.player_key = "zoe"
	_check(
		rebinds.size() == 1,
		"and a component is told when the person its node represents changes — a "
		+ "pooled node reused for the next spawn is exactly this case"
	)
	player.player_key = "ada"

	var remote_only := DotPlayerComponent.new()
	remote_only.local_only = true
	player.add_child(remote_only)
	_check(remote_only.is_active(), "a local-only component is active on a local player")
	player.is_local = false
	_check(
		not remote_only.is_active(),
		"and inert on somebody else's, so a server holding thirty players is not "
		+ "running thirty first-person cameras"
	)
	player.is_local = true

	var orphan := DotPlayerComponent.new()
	add_child(orphan)
	_check(not orphan.is_bound(), "a component outside a player binds to nothing")
	_check(not orphan.is_active(), "and is inert")
	_check(
		orphan.describe_lines()[0].contains("unbound"),
		"and says so — describe_lines rather than describe, because this base "
		+ "deliberately has no describe(): the family is not uniform about whether one "
		+ "returns a String or a Dictionary, and a base that fixed the type would make "
		+ "every subclass that disagrees a parse error"
	)

	_check(player.describe_lines().size() >= 3, "a player describes itself")
	_check(component.describe_lines().size() == 1, "and so does a component")
	_check(component.component_name() == "DotPlayerComponent", "by its class name")

	# Unbinding.
	player.remove_child(component)
	_check(not component.is_bound(), "leaving the tree unbinds a component")
	component.free()

	orphan.free()
	player.queue_free()
	roster.queue_free()


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
