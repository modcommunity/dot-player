This is the **player** asset for TMC's **Dot** collection. It is the row every other player-facing asset reads: who is in the session, what side they are on, whether they are in the world, and what represents them while they are.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Why this exists

Before it, a team lived in dot-match, a class lived in dot-loadout, an alive flag lived in dot-spectate and a key lived in dot-stats. Four dictionaries, keyed the same way, updated from four places — and disagreeing about anybody who reconnected.

`DotPlayerRoster` is the one row they all read.

## Install

Copy `addons/dot_player/` and `addons/dot_core/` into your project and enable both in *Project → Project Settings → Plugins*.

Requires Godot 4.7 or newer.

## Use

```gdscript
var roster := DotPlayerRoster.new()
roster.config = DotPlayerConfig.new()
add_child(roster)

roster.join("ada", "Ada", peer_id, tick)
roster.set_team("ada", &"blue")
roster.set_alive("ada", true)          # counts the spawn for you

# Once a tick or once a second: frees seats whose reconnect window is up.
roster.advance(tick)
```

On a client, the same class with `authoritative = false`:

```gdscript
mirror.apply_wire(payload)             # the whole roster, on connect
mirror.apply_row(row)                  # one changed row, after that
```

**A mirror decides nothing.** Every mutator on one is refused with `CODE_FORBIDDEN`, because a client that can quietly assign itself to a team is a client that will.

## A dropped connection is not a departure

`note_disconnected` holds the seat. `join` with the same key inside the window is a **rejoin**: the same record, the same team, the same score, the original join tick, a new peer id.

A player whose router hiccups mid-round and comes back to an empty scoreboard has, from their side, been punished for their hardware. `reconnect_window_sec = 0` collapses this into an immediate removal, which is what a lobby wants and a competitive match does not.

Held seats count towards `max_players` by default. Freeing the slot the moment a connection drops is how a full server lets a stranger take the place of the player who is reconnecting into it.

## `DotPlayer` is a container, not a character

It extends `Node` — deliberately not `CharacterBody3D`.

The moment it extends a body it has picked a dimension, and hungario is 2D while arena is 3D. Worse, it has picked a physics model: a spectator, a dead player and a player riding in a vehicle are all participants with no body of their own at that moment.

```
DotPlayer              player_key = "ada"
  CharacterBody3D      the body, found rather than inherited
  DotFpsController     a DotPlayerComponent
  DotPlayerChar        a DotPlayerComponent
  DotPlayerAnimDriver  a DotPlayerComponent
```

## `DotPlayerComponent` is why nothing needs a path

Every other player addon's node extends it, and every one of them finds its player by walking up rather than by an exported `NodePath` somebody set in a scene the spawner then instanced under a different parent.

Subclasses override `_on_bound` / `_on_unbound`, **not `_ready`** — because `_ready` runs before a spawner has assigned the key, and a component that read the key there would read an empty one and then silently do nothing for the rest of the round.

`is_active()` is the one call a subclass's `_process` starts with: it checks the bind and the `local_only` rule in one place, so thirty players on a server are not thirty slightly different copies of the same two conditions.

## What is in the box

| | |
| --- | --- |
| `DotPlayerRecord` | The row. Key, name, peer, team, class, character, alive, counters, metadata, and a wire form that tolerates missing fields. |
| `DotPlayerRoster` | Authoritative on one machine, mirrored on the rest. Join, rejoin, hold, expire, and a stable key order. |
| `DotPlayerConfig` | Capacity, the reconnect window, name handling. Layered the family's way. |
| `DotPlayer` | The node. Finds its roster, its body and its components; joins a group per key. |
| `DotPlayerComponent` | The base. Binds by walking up, is told when the key changes, knows whether it should be running. |

## Licence

MIT. See [LICENSE](LICENSE).
