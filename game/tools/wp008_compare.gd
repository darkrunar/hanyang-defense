extends SceneTree
## WP-008 AC-09: same seed, no construction vs a planned construction strategy
## on the build profile (Config.for_wp008: 4 initial structures, supply 240).
## Prints and writes a JSON with, per run: the supply timeline, the purchase
## timeline, stronghold damage, the outcome and the number of commands.
##
##   godot --headless --path . --script res://game/tools/wp008_compare.gd [-- --out=<abs>.json --limit=400 --strategy=all|<name>]
##
## Strategies are data (below): a list of purchases in the preparation phase
## and conditional purchases during the battle ("when the supply reaches the
## cost and the trigger time has passed"), plus the free recovery placement
## after the collapse. Every purchase goes through the real command
## (Battle.buy_structure); refusals are recorded, never hidden.

const Battle := preload("res://game/core/battle.gd")
const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const K_J: int = Placement.Kind.JANGSEUNG
const K_H: int = Placement.Kind.HWACHA
const K_B: int = Placement.Kind.BONGSU
const K_S: int = Placement.Kind.SENSOR

## name -> {prep: [[kind, anchor]], battle: [[after_t, kind, anchor]], recovery: anchor}
const STRATEGIES: Dictionary = {
    "no_build": {"prep": [], "battle": [], "recovery": TestMap.RECOVERY_B},
    # Preparation only (no battle purchases): the collapse comes early enough
    # for the free recovery to be placed and the run to continue from the inner district.
    "prep_only": {"prep": [[K_H, Vector2i(42, 25)], [K_J, Vector2i(44, 36)], [K_B, Vector2i(42, 29)]], "battle": [], "recovery": TestMap.RECOVERY_B},
    # Preparation: a second plaza hwacha near the 남대문 mouth + the west-lane
    # jangseung, then grow with kills: more hwacha around the plaza and a
    # second network node so the plaza guns share the southern sensor.
    "plaza_guns": {
        "prep": [[K_H, Vector2i(42, 25)], [K_J, Vector2i(44, 36)], [K_B, Vector2i(42, 29)]],
        "battle": [[0.0, K_H, Vector2i(50, 25)], [0.0, K_H, Vector2i(38, 27)], [0.0, K_H, Vector2i(58, 27)],
            [0.0, K_B, Vector2i(42, 21)], [0.0, K_H, Vector2i(44, 13)], [0.0, K_H, Vector2i(50, 13)]],
        "recovery": TestMap.RECOVERY_B,
    },
    # Preparation spends on network reach (bongsu chain + sensors) and one
    # jangseung; hwachas come from wave rewards.
    "network_first": {
        "prep": [[K_B, Vector2i(42, 29)], [K_B, Vector2i(42, 21)], [K_S, Vector2i(47, 15)], [K_J, Vector2i(44, 36)]],
        "battle": [[0.0, K_H, Vector2i(42, 25)], [0.0, K_H, Vector2i(50, 25)], [0.0, K_H, Vector2i(38, 27)],
            [0.0, K_H, Vector2i(58, 27)], [0.0, K_H, Vector2i(44, 13)]],
        "recovery": TestMap.RECOVERY_B,
    },
    # Both lanes funnelled with jangseung (the west lane and the west-south
    # gallery), guns bought as the supply comes in.
    "funnel": {
        "prep": [[K_J, Vector2i(44, 36)], [K_J, Vector2i(22, 28)], [K_H, Vector2i(42, 25)]],
        "battle": [[0.0, K_H, Vector2i(50, 25)], [0.0, K_B, Vector2i(42, 29)], [0.0, K_H, Vector2i(38, 27)],
            [0.0, K_H, Vector2i(58, 27)], [0.0, K_H, Vector2i(44, 13)], [0.0, K_H, Vector2i(50, 13)]],
        "recovery": TestMap.RECOVERY_B,
    },
}


func _initialize() -> void:
    var out_path: String = ""
    var limit: float = 400.0
    var which: String = "all"
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            out_path = arg.substr("--out=".length())
        elif arg.begins_with("--limit="):
            limit = float(arg.substr("--limit=".length()))
        elif arg.begins_with("--strategy="):
            which = arg.substr("--strategy=".length())
    var runs: Dictionary = {}
    for name: String in STRATEGIES:
        if which != "all" and which != name:
            continue
        runs[name] = _run(name, STRATEGIES[name], limit)
    var summary: Dictionary = {}
    for name: String in runs:
        var r: Dictionary = runs[name]
        summary[name] = {"outcome": r["outcome"], "ended_at": r["ended_at"], "collapse_sim_time": r["collapse_sim_time"],
            "core_hp": r["core_hp"], "outer_hp": r["outer_hp"], "kills": r["kills"], "outer_arrivals": r["outer_arrivals"],
            "core_arrivals": r["core_arrivals"], "supply_end": r["economy"]["supply"], "earned_kills": r["economy"]["earned_kills"],
            "earned_waves": r["economy"]["earned_waves"], "spent": r["economy"]["spent"], "purchases": r["economy"]["purchase_count"],
            "refusals": r["economy"]["refusal_total"], "commands": r["commands"], "balance_ok": r["economy"]["balance_ok"],
            "recovery": r["recovery"]}
        print("%-14s %-4s t=%6.1f collapse=%6.1f core=%3.0f outer=%4.0f kills=%4d arrivals=%3d/%2d supply=%4d (+k%d +w%d -s%d) buys=%d refusals=%d cmds=%d" % [
            name, r["outcome"], r["ended_at"], r["collapse_sim_time"], r["core_hp"], r["outer_hp"], r["kills"],
            r["outer_arrivals"], r["core_arrivals"], r["economy"]["supply"], r["economy"]["earned_kills"],
            r["economy"]["earned_waves"], r["economy"]["spent"], r["economy"]["purchase_count"], r["economy"]["refusal_total"], r["commands"]])
    var won: Array = []
    for name: String in summary:
        if summary[name]["outcome"] == "WON":
            won.append(name)
    var report: Dictionary = {"seed": Config.for_wp008().get_int("seed"), "limit_seconds": limit, "strategies": STRATEGIES.keys(),
        "winning_strategies": won, "summary": summary, "runs": runs}
    print(JSON.stringify({"winning_strategies": won, "summary": summary}))
    if out_path != "":
        var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
        if f != null:
            f.store_string(JSON.stringify(report, "  "))
            f.close()
            print("written: %s" % out_path)
    quit(0)


static func _anchor_of(v: Variant) -> Vector2i:
    return v if v is Vector2i else Vector2i(int(v[0]), int(v[1]))


static func _run(name: String, strat: Dictionary, limit: float) -> Dictionary:
    var cfg: Config = Config.for_wp008()
    var b: Battle = Battle.new(cfg)
    var dt: float = cfg.get_num("fixed_dt")
    var commands: int = 0
    var command_log: Array = []
    # --- preparation ---
    for e: Array in strat["prep"]:
        var res: Placement.Result = b.buy_structure(int(e[0]), _anchor_of(e[1]))
        commands += 1
        command_log.append({"phase": "preparing", "t": 0.0, "kind": Placement.kind_name(int(e[0])), "anchor": [_anchor_of(e[1]).x, _anchor_of(e[1]).y],
            "ok": res.ok, "reason": Placement.reject_name(res.reason), "supply": b.economy.supply})
    var supply_after_prep: int = b.economy.supply
    b.begin_defense()
    # --- battle ---
    var pending: Array = (strat["battle"] as Array).duplicate(true)
    var recovery_anchor: Vector2i = _anchor_of(strat["recovery"])
    var timeline: Array = []
    var last_sec: int = -1
    var recovered: bool = false
    var recovery_result: String = ""
    while b.sim_time < limit and not b.run.ended():
        b.step(dt)
        # free recovery as soon as the right exists (retry while the cell is occupied)
        if b.run.recovery_right > 0 and not recovered:
            var rr: Placement.Result = b.place_recovery(recovery_anchor)
            commands += 1
            if rr.ok:
                recovered = true
                recovery_result = "ok@%.1f" % b.sim_time
                command_log.append({"phase": "battle", "t": b.sim_time, "recovery": [recovery_anchor.x, recovery_anchor.y], "ok": true})
        # planned purchases: first pending entry whose time has passed and cost is covered
        if not pending.is_empty():
            var e: Array = pending[0]
            if b.sim_time >= float(e[0]) and b.economy.can_afford(int(e[1])):
                var res: Placement.Result = b.buy_structure(int(e[1]), _anchor_of(e[2]))
                commands += 1
                command_log.append({"phase": "battle", "t": b.sim_time, "kind": Placement.kind_name(int(e[1])),
                    "anchor": [_anchor_of(e[2]).x, _anchor_of(e[2]).y], "ok": res.ok, "reason": Placement.reject_name(res.reason), "supply": b.economy.supply})
                if res.ok or res.reason != Placement.Reject.ENEMY_OCCUPIES_CELL:
                    pending.pop_front()
        var sec: int = int(floor(b.sim_time))
        if sec != last_sec:
            last_sec = sec
            timeline.append({"sec": sec, "supply": b.economy.supply, "earned_kills": b.economy.earned_kills, "earned_waves": b.economy.earned_waves,
                "spent": b.economy.spent, "alive": b.sim.alive_count, "killed": b.sim.killed_total, "outer_hp": b.run.outer_hp,
                "core_hp": b.run.core_hp, "wave": b.waves.snapshot()["wave_name"], "structures": b.structure_total(),
                "run": b.run.run_name(), "defense": b.run.defense_name()})
    return {
        "strategy": name, "outcome": b.run.run_name(), "ended_at": b.sim_time, "collapse_sim_time": b.run.collapse_sim_time,
        "core_hp": b.run.core_hp, "outer_hp": b.run.outer_hp, "kills": b.sim.killed_total, "outer_arrivals": b.run.outer_arrivals,
        "core_arrivals": b.run.core_arrivals, "spawned": b.sim.spawned_total, "supply_after_preparation": supply_after_prep,
        "economy": b.economy.snapshot(), "commands": commands, "command_log": command_log, "recovery": recovery_result if recovered else ("no_right" if b.run.collapse_count == 0 else "not_placed"),
        "timeline": timeline, "waves": b.waves.snapshot(), "forced_hp_writes": b.run.forced_hp_writes,
        "structures_end": b.structure_total(), "state_hash": b.state_hash(),
    }
