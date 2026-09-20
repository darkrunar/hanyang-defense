extends RefCounted
## WP-008 supply ledger (backlog/WP-008.md "경제·건설 규칙", D-054).
##
##  * integer supply, run-scoped: reset() on every new run, nothing carries over
##  * income: +kill_reward per real kill (first death transition of a living
##    enemy, counted once per individual), +wave_reward once per wave when the
##    wave's whole budget has spawned AND every enemy of it has been resolved
##  * spending: one purchase = one charge, only after the placement succeeded
##  * invariant after every operation (tests assert it):
##        supply == start_supply + earned_kills + earned_waves + injected - spent
##  * every change is an event with tick + sequence number
##
## `injected` is the benchmark-only supply (config benchmark_supply); it is
## flagged so a perf run can never pass as a normal-economy result.

const Placement := preload("res://game/core/placement.gd")

var enabled: bool = false
var start_supply: int = 0
var supply: int = 0
var earned_kills: int = 0
var earned_waves: int = 0
var spent: int = 0
var injected: int = 0
var kill_reward: int = 1
var wave_reward: int = 80
var cap: int = 24
var costs: Dictionary = {}          # Placement.Kind -> cost

var kills_rewarded: int = 0
var waves_rewarded: Array = []      # wave indices, in payment order
var purchases: Array = []           # {seq, tick, sim_time, kind, anchor, cost, id, label, phase}
var purchases_by_kind: Dictionary = {}
var refusals: Dictionary = {}       # reject name -> count
var refusal_log: Array = []
const REFUSAL_LOG_CAP: int = 256
var events: Array = []
var _seq: int = 0


func configure(start: int, kill_r: int, wave_r: int, cost_by_kind: Dictionary, cap_total: int) -> void:
    start_supply = maxi(0, start)
    kill_reward = maxi(0, kill_r)
    wave_reward = maxi(0, wave_r)
    costs = cost_by_kind.duplicate()
    cap = maxi(0, cap_total)


func reset() -> void:
    supply = start_supply if enabled else 0
    earned_kills = 0
    earned_waves = 0
    spent = 0
    injected = 0
    kills_rewarded = 0
    waves_rewarded.clear()
    purchases.clear()
    purchases_by_kind.clear()
    refusals.clear()
    refusal_log.clear()
    events.clear()
    _seq = 0


func balance_ok() -> bool:
    return supply == start_supply + earned_kills + earned_waves + injected - spent


func _event(tick: int, sim_time: float, type: String, data: Dictionary) -> void:
    _seq += 1
    var e: Dictionary = {"seq": _seq, "tick": tick, "sim_time": sim_time, "type": type, "supply": supply}
    for k: Variant in data:
        if k == "seq":
            continue   # never let payload overwrite the ledger ordinal (R-03)
        e[k] = data[k]
    events.append(e)


## True when every event seq is 1..n in order with no duplicate (R-03 regression).
func events_well_ordered() -> bool:
    for i: int in range(events.size()):
        if int(events[i]["seq"]) != i + 1:
            return false
    return true


## `n` real kills this tick (the EnemySim killed_total delta). Returns the
## supply paid. Arrivals are never passed here (they are leaks, not kills).
func reward_kills(n: int, tick: int, sim_time: float) -> int:
    if not enabled or n <= 0:
        return 0
    var paid: int = n * kill_reward
    supply += paid
    earned_kills += paid
    kills_rewarded += n
    _event(tick, sim_time, "kill_reward", {"kills": n, "paid": paid})
    return paid


## Pay the wave bonus for `index` exactly once. Returns false when it was
## already paid (duplicate clear detection) or the ledger is off.
func reward_wave(index: int, tick: int, sim_time: float) -> bool:
    if not enabled or index < 0 or waves_rewarded.has(index):
        return false
    supply += wave_reward
    earned_waves += wave_reward
    waves_rewarded.append(index)
    _event(tick, sim_time, "wave_reward", {"wave_index": index, "paid": wave_reward})
    return true


func cost_of(kind: int) -> int:
    return int(costs.get(kind, 0))


func can_afford(kind: int) -> bool:
    return supply >= cost_of(kind)


## Charge one purchase AFTER the structure exists. Returns the cost.
func charge(kind: int, tick: int, sim_time: float, anchor: Vector2i, id: int, label: String, phase: String) -> int:
    var cost: int = cost_of(kind)
    supply -= cost
    spent += cost
    # GPT review R-03 (PR #13): the purchase ordinal is "purchase_seq"; the
    # event ledger's "seq" is set by _event() alone and stays monotonic.
    var rec: Dictionary = {"purchase_seq": purchases.size() + 1, "tick": tick, "sim_time": sim_time, "kind": Placement.kind_name(kind),
        "anchor": [anchor.x, anchor.y], "cost": cost, "id": id, "label": label, "phase": phase, "supply_after": supply}
    purchases.append(rec)
    purchases_by_kind[Placement.kind_name(kind)] = int(purchases_by_kind.get(Placement.kind_name(kind), 0)) + 1
    _event(tick, sim_time, "purchase", rec)
    return cost


func refuse(reason: int, kind: int, anchor: Vector2i, tick: int, sim_time: float) -> void:
    var name: String = Placement.reject_name(reason)
    refusals[name] = int(refusals.get(name, 0)) + 1
    if refusal_log.size() < REFUSAL_LOG_CAP:
        refusal_log.append({"tick": tick, "sim_time": sim_time, "reason": name, "kind": Placement.kind_name(kind),
            "anchor": [anchor.x, anchor.y], "supply": supply})


## Benchmark-only injection (flagged in every snapshot / manifest).
func inject(amount: int, tick: int, sim_time: float, why: String) -> void:
    if amount <= 0:
        return
    supply += amount
    injected += amount
    _event(tick, sim_time, "benchmark_inject", {"amount": amount, "why": why})


func refusal_total() -> int:
    var n: int = 0
    for k: Variant in refusals:
        n += int(refusals[k])
    return n


func snapshot() -> Dictionary:
    var cost_names: Dictionary = {}
    for k: Variant in costs:
        cost_names[Placement.kind_name(int(k))] = int(costs[k])
    return {
        "enabled": enabled,
        "start_supply": start_supply,
        "supply": supply,
        "earned_kills": earned_kills,
        "earned_waves": earned_waves,
        "spent": spent,
        "injected": injected,
        "benchmark_injected": injected > 0,
        "balance_ok": balance_ok(),
        "kill_reward": kill_reward,
        "wave_reward": wave_reward,
        "cap": cap,
        "costs": cost_names,
        "kills_rewarded": kills_rewarded,
        "waves_rewarded": waves_rewarded.duplicate(),
        "purchase_count": purchases.size(),
        "events_well_ordered": events_well_ordered(),
        "purchases": purchases.duplicate(true),
        "purchases_by_kind": purchases_by_kind.duplicate(),
        "refusals": refusals.duplicate(),
        "refusal_total": refusal_total(),
        "event_count": events.size(),
    }
