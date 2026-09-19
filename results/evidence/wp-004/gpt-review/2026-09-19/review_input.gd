extends SceneTree
const Helpers = preload("res://tests/test_play_flow.gd")
const DT = 0.0166666667
func _initialize():
    call_deferred("run_review")
func run_review():
    var s = Helpers._new_scene(self, "user://wp004_review_missing.cfg")
    Helpers._start(s)
    Helpers._force_collapse(s)
    s._cursor_world_override = Vector2(900, 280)
    Helpers._key(s, KEY_ESCAPE)
    Helpers._frame(s)
    Helpers._key(s, KEY_ESCAPE, false)
    Helpers._key(s, KEY_ESCAPE, true)
    Helpers._frame(s)
    var before = s.battle.commands_accepted
    # Esc that closed PAUSED is still held: no release was sent.
    Helpers._lmb(s, true)
    var release_fence = {"case": "resume_esc_still_held_then_lmb", "expected_accepted_delta": 0, "actual_accepted_delta": s.battle.commands_accepted-before, "recovery_placed": s.battle.run.recovery_placed, "state": s.flow.state_name()}
    Helpers._drop(s)
    # Probe the explicit already-ended/pending-intent contract separately.
    s = Helpers._new_scene(self, "user://wp004_review_missing.cfg")
    Helpers._start(s)
    Helpers._force_collapse(s)
    s.battle.force_core_hp(1, "review terminal boundary")
    s.battle.spawn_extra(Vector2(950,210),1,"review last arrival")
    s.queue_intent("pause")
    s.battle.step(DT)
    var terminal_before = s.battle.run.run_name()
    Helpers._frame(s)
    var terminal = {"case":"already_ended_before_pending_pause", "run_before_dispatch":terminal_before, "expected_ui":"RESULT", "actual_ui":s.flow.state_name(), "note":"explicit boundary injection; ordinary loop checks end in same callback"}
    Helpers._drop(s)
    var routed = await routed_input()
    var out = {"release_fence":release_fence,"terminal_boundary":terminal,"viewport_input":routed}
    print(JSON.stringify(out))
    var f=FileAccess.open("res://results/evidence/wp-004/gpt-review/2026-09-19/input_review.json",FileAccess.WRITE)
    f.store_string(JSON.stringify(out,"  ")+"\n")
    quit()

func routed_input():
    var s = Helpers._new_scene(self, "user://wp004_review_missing.cfg")
    Helpers._start(s)
    Helpers._force_collapse(s)
    s._cursor_world_override = Vector2(900,280)
    await process_frame
    var ev = InputEventKey.new()
    ev.keycode = KEY_ESCAPE
    ev.pressed = true
    root.push_input(ev)
    Helpers._frame(s)
    ev = InputEventKey.new()
    ev.keycode = KEY_ESCAPE
    ev.pressed = false
    root.push_input(ev)
    await process_frame
    var paused = s.flow.state_name()
    ev = InputEventKey.new()
    ev.keycode = KEY_ESCAPE
    ev.pressed = true
    root.push_input(ev)
    Helpers._frame(s)
    await process_frame
    var before = s.battle.commands_accepted
    var mb = InputEventMouseButton.new()
    mb.button_index = MOUSE_BUTTON_LEFT
    mb.position = Vector2(900,280)
    mb.global_position = mb.position
    mb.pressed = true
    root.push_input(mb)
    var result = {"paused":paused,"after_resume":s.flow.state_name(),"esc_release_sent":false,"accepted_delta":s.battle.commands_accepted-before,"recovery_placed":s.battle.run.recovery_placed}
    Helpers._drop(s)
    return result