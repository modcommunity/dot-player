# dot-player

Who is in the session, and what represents them while they are in the world.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first — no autoloads, `DotNodeRef` instead of scene paths, `DotResult` for anything fallible, `Dot`-prefixed class names, layered configuration, `describe()` on anything stateful. This file is only what is specific to players.

## The one idea

**There is exactly one row per participant, and everything else reads it.**

This addon exists because there were four. A team lived in dot-match, a class in dot-loadout, an alive flag in dot-spectate and a key in dot-stats: four dictionaries keyed the same way, written from four places, and guaranteed to disagree about anybody who reconnected. `DotPlayerRecord` is the row; `DotPlayerRoster` owns it; nothing else should keep a parallel dictionary keyed by player.

The second idea is the one that shapes the nodes: **a player node is a container, not a character.** `DotPlayer extends Node`. The moment it extends a body it has chosen a dimension — and this family ships 2D and 3D games — and it has chosen a physics model, when a spectator, a dead player and a passenger in a vehicle are all participants with no body of their own.

## Layout

```
addons/dot_player/
  core/
    dot_player_record.gd      the row, and its wire form
    dot_player_config.gd      capacity, the reconnect window, names
  runtime/
    dot_player_roster.gd      authoritative on one machine, mirrored on the rest
  nodes/
    dot_player.gd             the container, and how one is found
    dot_player_component.gd   the base every other player addon extends
```

## A drop is not a departure, and the difference is load-bearing

`note_disconnected` holds the seat; `join` with the same key inside the window is a rejoin that returns everything. A player whose router hiccups mid-round and returns to an empty scoreboard has, from their side, been punished for their hardware.

Two details that look like details and are not:

- **The original `joined_tick` survives.** "Time in the session" is then still true, which is what a session-length statistic and an idle-kick both read.
- **A held seat counts towards `max_players`.** Freeing it immediately is how a full server lets a stranger take the slot of the player reconnecting into it.

`advance(tick)` is what actually expires a window. A window only checked when somebody tries to rejoin is a window that never expires, and the roster then grows for the whole uptime of the server — the same shape as `DotSpawnProtection.advance` and as the unbounded recorder in `docs/bugs-found.md`.

## `authoritative` is a flag, not a second class

One class, two configurations. A mirror refuses every mutator with `CODE_FORBIDDEN` and an authoritative roster refuses `apply_wire` — because a server that can be told what its own roster is by a packet has no roster at all. The pattern is dot-spectate's, and the reason is the same one: a listen server needs both in one process, which rules out a singleton.

`_order` is a `PackedStringArray` beside the dictionary, and `keys()` returns it. A `Dictionary`'s iteration order is an implementation detail, and two machines iterating one differently produce scoreboards that disagree about who is first — which reads as a sorting bug in the UI rather than as this.

## `_on_bound`, not `_ready`

The single most important thing for anybody writing a component. A spawner does:

```gdscript
var p := PLAYER_SCENE.instantiate()
add_child(p)          # every _ready in the subtree runs HERE
p.player_key = "ada"  # and the key arrives HERE
```

A component that read `player_key` in `_ready` reads an empty string and then does nothing at all for the rest of the round, with no error anywhere. `_on_bound` is called on the bind and again on every key change, and **must be safe to call twice** — a pooled player node reused for the next spawn calls it again with the same node and a different person.

`is_active()` folds the bind check and the `local_only` rule together on purpose. Thirty players on a server would otherwise be thirty copies of the same two conditions, written slightly differently, one of them wrong.

## Small decisions with reasons

`component(&"DotPlayerComponent")` looks up **by class name**, walking the script chain, rather than by type. dot-player cannot import dot-weapon or dot-player-controller — it is the base they depend on, not the other way round — so a name is the only thing it can match on.

`_gather_components` does not descend past a nested `DotPlayer`. A player node inside another one is a vehicle passenger or a character preview, and its components are not this player's.

`key_of_peer` is a linear scan. A reverse index is a second copy of the truth, and the one place it would help is already doing more work per packet than this.

`spawn_team()` is named for its caller: dot-spawn duck-types `spawn_team` on whatever entered an area, and having the player node answer it saves a two-line adapter on every body in every game.

`world_position()` returns a `Vector3` in both dimensions, with Z unused in 2D. Every consumer — spawn danger scoring, a spectator camera, a HUD compass — otherwise needs its own branch, and one of them gets it wrong.

## What this does not do

It does not spawn, move, render, animate or damage anything. It does not talk to a transport: `to_wire` / `apply_wire` produce and consume dictionaries, and dot-net or a game's own bridge carries them.

It also does not validate a display name beyond trimming and truncating. dot-user is where identity rules belong, and bouncing somebody off a server over text length is worse than shortening it.
