extends RefCounted
## WP-003 finite waves (backlog/WP-003.md §4, D-025).
##
##  * each wave has a per-route budget and per-route rate (enemies / second)
##  * a fixed-tick accumulator spawns floor(accum) per route each tick, routes in
##    the stable order south -> west -> east
##  * the next wave starts `gap_seconds` after the current wave's budget is spent
##    AND no enemy is alive
##  * a collapse never resets budgets or timers
##  * `scheduled_complete` is true once the LAST wave's budget is spent; the
##    battle turns that + alive == 0 + core alive into WON

const EnemySim := preload("res://game/core/enemy_sim.gd")

enum State { SPAWNING, WAITING_CLEAR, GAP, DONE }
const STATE_NAMES: Array[String] = ["SPAWNING", "WAITING_CLEAR", "GAP", "DONE"]

var waves: Array = []            # [{name, count:[s,w,e], rate:[s,w,e]}]
var gap_seconds: float = 5.0
var enabled: bool = true

var current: int = 0
var state: int = State.SPAWNING
var remaining: PackedInt32Array = PackedInt32Array()
var accum: PackedFloat32Array = PackedFloat32Array()
var gap_left: float = 0.0
var spawned_by_wave: PackedInt32Array = PackedInt32Array()
var spawned_scheduled: int = 0
## Extra enemies the scenarios add outside the wave table (F2 +1, F3 +12).
var spawned_extra: int = 0
var wave_started_tick: PackedInt32Array = PackedInt32Array()
var wave_spent_tick: PackedInt32Array = PackedInt32Array()


func configure(table: Array, gap: float, routes: int) -> void:
    waves = table.duplicate(true)
    gap_seconds = gap
    remaining.resize(routes)
    accum.resize(routes)
    reset()


func reset() -> void:
    current = 0
    spawned_scheduled = 0
    spawned_extra = 0
    spawned_by_wave.resize(waves.size())
    spawned_by_wave.fill(0)
    wave_started_tick.resize(waves.size())
    wave_started_tick.fill(-1)
    wave_spent_tick.resize(waves.size())
    wave_spent_tick.fill(-1)
    gap_left = 0.0
    if waves.is_empty():
        state = State.DONE
        return
    _start_wave(0, 0)


func _start_wave(index: int, tick: int) -> void:
    current = index
    state = State.SPAWNING
    var counts: Array = waves[index]["count"]
    for r: int in range(remaining.size()):
        remaining[r] = int(counts[r]) if r < counts.size() else 0
        accum[r] = 0.0
    wave_started_tick[index] = tick
    if _all_spent():
        state = State.WAITING_CLEAR
        wave_spent_tick[index] = tick


func _all_spent() -> bool:
    for r: int in range(remaining.size()):
        if remaining[r] > 0:
            return false
    return true


func total_budget() -> int:
    var n: int = 0
    for w: Dictionary in waves:
        for c: Variant in w["count"]:
            n += int(c)
    return n


func scheduled_complete() -> bool:
    return state == State.DONE or (current == waves.size() - 1 and state != State.SPAWNING)


func is_last_wave() -> bool:
    return current >= waves.size() - 1


func state_name() -> String:
    return STATE_NAMES[state]


## One fixed tick. Returns the number of enemies spawned this tick.
func step(dt: float, tick: int, sim: EnemySim) -> int:
    if not enabled or state == State.DONE:
        return 0
    var spawned: int = 0
    match state:
        State.SPAWNING:
            var rates: Array = waves[current]["rate"]
            for r: int in range(remaining.size()):   # stable route order 0,1,2
                if remaining[r] <= 0:
                    continue
                accum[r] += float(rates[r]) * dt
                var n: int = int(accum[r])
                if n <= 0:
                    continue
                accum[r] -= float(n)
                n = mini(n, remaining[r])
                var made: int = sim.spawn_on_route(r, n)
                remaining[r] -= made
                spawned += made
            spawned_by_wave[current] += spawned
            spawned_scheduled += spawned
            if _all_spent():
                state = State.WAITING_CLEAR
                wave_spent_tick[current] = tick
        State.WAITING_CLEAR:
            if sim.alive_count == 0:
                if is_last_wave():
                    state = State.DONE
                else:
                    state = State.GAP
                    gap_left = gap_seconds
        State.GAP:
            gap_left -= dt
            if gap_left <= 0.0:
                _start_wave(current + 1, tick)
    return spawned


func snapshot() -> Dictionary:
    var rem: Array = []
    for r: int in range(remaining.size()):
        rem.append(remaining[r])
    return {
        "enabled": enabled,
        "wave_index": current,
        "wave_name": waves[current]["name"] if current < waves.size() else "",
        "state": state_name(),
        "remaining": rem,
        "gap_left": gap_left,
        "spawned_scheduled": spawned_scheduled,
        "spawned_extra": spawned_extra,
        "spawned_by_wave": Array(spawned_by_wave),
        "total_budget": total_budget(),
        "scheduled_complete": scheduled_complete(),
        "wave_started_tick": Array(wave_started_tick),
        "wave_spent_tick": Array(wave_spent_tick),
    }
