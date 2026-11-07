# dot-player

Who is in the session, and what represents them while they are in the world. `DotPlayerRoster` holds exactly one `DotPlayerRecord` per participant (authoritative on one machine, mirrored on the rest); `DotPlayer` is a plain `Node` container in the world, and `DotPlayerComponent` is the base every other player addon extends.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/dot_player/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing anything, or writing a component: one row, container not character, reconnects, mirrors, `_on_bound`, lookups by name, names |

## Layout

| Path | What |
| --- | --- |
| `core/dot_player_record.gd` | `DotPlayerRecord`: the row (key, name, peer, team, class, char, alive, bot, `joined_tick`) and its wire form |
| `core/dot_player_config.gd` | `DotPlayerConfig`: capacity, bots, reserved seats, the reconnect window, names |
| `runtime/dot_player_roster.gd` | `DotPlayerRoster`: `join`, `join_bot`, `note_disconnected`, `remove`, `advance`, setters, listings, `to_wire` / `apply_wire` |
| `nodes/dot_player.gd` | `DotPlayer`: the container; `record()`, `component()`, `spawn_team()`, `world_position()` |
| `nodes/dot_player_component.gd` | `DotPlayerComponent`: `_on_bound`, `_on_unbound`, `is_active()`, `local_only` |
| `examples/player_selftest.tscn` | the suite |

Paths except `examples/` are in `addons/dot_player/`.

## Running and testing

The family's two steps ([family CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/player_selftest.tscn`.

## Rules that bite

- One row per participant: never keep a parallel dictionary keyed by player elsewhere. [design](docs/design.md#the-one-idea)
- `DotPlayer` extends `Node`, never a body. [design](docs/design.md#the-one-idea)
- A disconnect holds the seat; a rejoin inside the window keeps `joined_tick`, and the held seat counts towards `max_players`. [design](docs/design.md#a-drop-is-not-a-departure-and-the-difference-is-load-bearing)
- Call `advance(tick)`, or reconnect windows never expire. [design](docs/design.md#a-drop-is-not-a-departure-and-the-difference-is-load-bearing)
- A mirror refuses mutators with `CODE_FORBIDDEN`; an authoritative roster refuses `apply_wire`. [design](docs/design.md#authoritative-is-a-flag-not-a-second-class)
- Order comes from `_order` / `keys()`, never dictionary iteration. [design](docs/design.md#authoritative-is-a-flag-not-a-second-class)
- A component reads its player in `_on_bound`, never `_ready`, and `_on_bound` must be safe to call twice. [design](docs/design.md#_on_bound-not-_ready)
- dot-player never imports the addons built on it; `component()` matches by class name. [design](docs/design.md#small-decisions-with-reasons)
- Names are cleaned and made unique, never refused. [design](docs/design.md#names-are-cleaned-never-refused)

Deliberately not here: spawning, moving, rendering, damage, a transport. [design](docs/design.md#what-this-does-not-do)
