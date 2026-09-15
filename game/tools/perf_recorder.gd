extends RefCounted
## Frame-time recorder for the WP-001 performance contract.
##
## Records wall-clock frame intervals during the measurement window and
## reports average FPS, p50/p95/p99 frame time, and static memory. Written as
## JSON so the result document can quote the raw evidence.

var scenario: String = ""
var warmup_seconds: float = 10.0
var measure_seconds: float = 60.0

var _phase: String = "idle"   # idle -> warmup -> measure -> done
var _phase_started_usec: int = 0
var _last_frame_usec: int = 0
var _frame_us: PackedInt64Array = PackedInt64Array()
var _phys_us: PackedInt64Array = PackedInt64Array()   # TIME_PHYSICS_PROCESS monitor per rendered frame
var _alive_samples: PackedInt32Array = PackedInt32Array()
var _per_second: Array = []
var _sec_accum_us: int = 0
var _sec_frames: int = 0
var _sec_index: int = 0
var _mem_start: int = 0
var _mem_peak: int = 0
var extra: Dictionary = {}


func is_done() -> bool:
    return _phase == "done"


func phase() -> String:
    return _phase


func elapsed_in_phase() -> float:
    return float(Time.get_ticks_usec() - _phase_started_usec) / 1e6


func start() -> void:
    _phase = "warmup"
    _phase_started_usec = Time.get_ticks_usec()
    _last_frame_usec = _phase_started_usec
    _frame_us.clear()
    _phys_us.clear()
    _alive_samples.clear()
    _per_second.clear()


## Call once per rendered frame with the current concurrent alive count.
## Wall-clock interval of the most recent frame (microseconds), for callers
## that keep their own per-segment statistics.
var last_frame_us: int = 0


func tick(alive: int) -> void:
    var now: int = Time.get_ticks_usec()
    var dt_us: int = now - _last_frame_usec
    _last_frame_usec = now
    last_frame_us = dt_us
    match _phase:
        "warmup":
            if float(now - _phase_started_usec) / 1e6 >= warmup_seconds:
                _phase = "measure"
                _phase_started_usec = now
                _mem_start = OS.get_static_memory_usage()
                _mem_peak = _mem_start
                _sec_accum_us = 0
                _sec_frames = 0
                _sec_index = 0
        "measure":
            _frame_us.append(dt_us)
            _phys_us.append(int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1e6))
            _alive_samples.append(alive)
            _sec_accum_us += dt_us
            _sec_frames += 1
            var mem: int = OS.get_static_memory_usage()
            if mem > _mem_peak:
                _mem_peak = mem
            if _sec_accum_us >= 1_000_000:
                _per_second.append({
                    "t": _sec_index,
                    "fps": float(_sec_frames) * 1e6 / float(_sec_accum_us),
                    "alive": alive,
                    "mem_mb": float(mem) / 1048576.0,
                })
                _sec_index += 1
                _sec_accum_us = 0
                _sec_frames = 0
            if float(now - _phase_started_usec) / 1e6 >= measure_seconds:
                _phase = "done"


static func _percentile(sorted: PackedInt64Array, p: float) -> float:
    if sorted.is_empty():
        return 0.0
    var idx: int = int(ceil(p / 100.0 * float(sorted.size()))) - 1
    idx = clampi(idx, 0, sorted.size() - 1)
    return float(sorted[idx]) / 1000.0


func report() -> Dictionary:
    var sorted: PackedInt64Array = _frame_us.duplicate()
    sorted.sort()
    var phys_sorted: PackedInt64Array = _phys_us.duplicate()
    phys_sorted.sort()
    var phys_total: int = 0
    for v: int in _phys_us:
        phys_total += v
    var total_us: int = 0
    for v: int in _frame_us:
        total_us += v
    var frames: int = _frame_us.size()
    var alive_min: int = 0
    var alive_max: int = 0
    var alive_sum: int = 0
    if not _alive_samples.is_empty():
        alive_min = _alive_samples[0]
        alive_max = _alive_samples[0]
        for a: int in _alive_samples:
            alive_min = mini(alive_min, a)
            alive_max = maxi(alive_max, a)
            alive_sum += a
    var out: Dictionary = {
        "scenario": scenario,
        "engine": "Godot %s" % Engine.get_version_info().string,
        "renderer": RenderingServer.get_current_rendering_method(),
        "rendering_driver": RenderingServer.get_current_rendering_driver_name(),
        "adapter": RenderingServer.get_video_adapter_name(),
        "adapter_api": RenderingServer.get_video_adapter_api_version(),
        "os": "%s %s" % [OS.get_name(), OS.get_version()],
        "cpu": OS.get_processor_name(),
        "cpu_threads": OS.get_processor_count(),
        "window_size": str(DisplayServer.window_get_size()),
        "window_mode": DisplayServer.window_get_mode(),
        "vsync_mode": DisplayServer.window_get_vsync_mode(),
        "build": "editor/project run" if OS.has_feature("editor") else (
            "exported debug" if OS.is_debug_build() else "exported release"
        ),
        "warmup_seconds": warmup_seconds,
        "measure_seconds": measure_seconds,
        "measured_seconds": float(total_us) / 1e6,
        "frames": frames,
        "avg_fps": (float(frames) * 1e6 / float(total_us)) if total_us > 0 else 0.0,
        "frame_ms_avg": (float(total_us) / float(frames) / 1000.0) if frames > 0 else 0.0,
        "frame_ms_p50": _percentile(sorted, 50.0),
        "frame_ms_p95": _percentile(sorted, 95.0),
        "frame_ms_p99": _percentile(sorted, 99.0),
        "frame_ms_max": (float(sorted[sorted.size() - 1]) / 1000.0) if frames > 0 else 0.0,
        # Cost of one 60 Hz simulation tick as seen by the engine's physics-step
        # monitor, sampled once per rendered frame (repeats between ticks).
        "sim_step_ms_avg": (float(phys_total) / float(_phys_us.size()) / 1000.0) if not _phys_us.is_empty() else 0.0,
        "sim_step_ms_p95": _percentile(phys_sorted, 95.0),
        "sim_step_ms_max": (float(phys_sorted[phys_sorted.size() - 1]) / 1000.0) if not phys_sorted.is_empty() else 0.0,
        # OS.get_static_memory_usage() is compiled out of release templates (0);
        # the external sampler in scripts/perf_with_memory.ps1 records the real
        # process working set alongside this file.
        "memory_note": "static memory counters are 0 in release templates; see *.memory.json",
        "alive_min": alive_min,
        "alive_max": alive_max,
        "alive_avg": (float(alive_sum) / float(frames)) if frames > 0 else 0.0,
        "memory_static_mb_start": float(_mem_start) / 1048576.0,
        "memory_static_mb_end": float(OS.get_static_memory_usage()) / 1048576.0,
        "memory_static_mb_peak_in_window": float(_mem_peak) / 1048576.0,
        "memory_static_mb_process_peak": float(OS.get_static_memory_peak_usage()) / 1048576.0,
        "per_second": _per_second,
        # Raw per-frame wall-clock intervals (microseconds), in order, so a
        # reviewer can recompute every percentile independently (GPT review).
        "frame_us_raw": Array(_frame_us),
        "alive_raw": Array(_alive_samples),
    }
    for k: String in extra:
        out[k] = extra[k]
    if extra.has("target_alive"):
        # The D-009 load requirement, evaluated on every measured frame.
        out["load_held_all_frames"] = alive_min >= int(extra["target_alive"])
    return out
