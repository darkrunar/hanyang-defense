extends RefCounted
## WP-004 (D-039 / D-040): the top-level UI state of a normal launch, kept
## strictly apart from the battle's RunState. The scene asks this machine
## whether a transition is legal, performs the side effects it names
## (start a new run, apply a setting, quit) and renders the state.
##
##   TITLE ─start─▶ PLAYING ─pause─▶ PAUSED ─resume─▶ PLAYING
##   TITLE / PAUSED ─settings─▶ SETTINGS ─back─▶ (where it came from)
##   PLAYING(R) / PAUSED ─restart / to_title─▶ CONFIRM ─ok─▶ new run / TITLE
##                                            CONFIRM ─cancel─▶ (where it came from)
##   PLAYING ─run ended─▶ RESULT ─restart / to_title─▶ new run / TITLE (no confirm)
##
## Every accepted transition is logged with a sequence number; refused
## requests are counted so a double-click / key repeat can be proven to
## have produced exactly one transition.

## WP-008 (D-054): PREPARING sits between TITLE and PLAYING in build mode
## (start_game -> PREPARING -> begin_defense -> PLAYING). The field accepts
## placement input in PREPARING, the battle ticks only in PLAYING; a pause
## returns to the state it interrupted.
enum State { TITLE, PLAYING, PAUSED, SETTINGS, CONFIRM, RESULT, PREPARING }
const STATE_NAMES: Array[String] = ["TITLE", "PLAYING", "PAUSED", "SETTINGS", "CONFIRM", "RESULT", "PREPARING"]

## Actions the scene must perform after an accepted transition.
const ACT_NONE: String = ""
const ACT_NEW_RUN: String = "new_run"        # start a fresh run from the initial data
const ACT_TO_TITLE: String = "to_title"      # discard the current run, show the title
const ACT_QUIT: String = "quit"
const ACT_BEGIN_DEFENSE: String = "begin_defense"   # WP-008: PREPARING -> PLAYING, start the waves

const CONFIRM_RESTART: String = "restart"
const CONFIRM_TO_TITLE: String = "to_title"

const CONFIRM_TEXT: Dictionary = {
    "restart": {"text": "현재 전투를 종료하고 처음부터 시작할까요?", "ok": "다시 시작", "cancel": "취소"},
    "to_title": {"text": "현재 전투를 종료하고 시작 화면으로 돌아갈까요? 진행 상황은 저장되지 않습니다.", "ok": "시작 화면으로", "cancel": "취소"},
}

var state: int = State.TITLE
## WP-008: a build-mode launch starts every run in PREPARING.
var build_mode: bool = false
## Where SETTINGS returns to (TITLE or PAUSED), where CONFIRM returns to on
## cancel (PLAYING, PREPARING or PAUSED) and where PAUSED resumes to
## (PLAYING or PREPARING).
var settings_return: int = State.TITLE
var confirm_return: int = State.PLAYING
var pause_return: int = State.PLAYING
var confirm_kind: String = ""
## Frozen result model (D-041); null outside RESULT.
var result: Dictionary = {}
## Scripted / automated modes bypass the menus entirely (WP-004 §6).
var bypass: bool = false

var transitions: Array = []      # [{seq, from, to, request}]
var refused: Array = []          # [{seq, state, request}]
var _seq: int = 0


func state_name() -> String:
    return STATE_NAMES[state]


## True while the battle may advance.
func battle_active() -> bool:
    return state == State.PLAYING


## True while the field accepts placement input (battle ticking or preparing).
func field_active() -> bool:
    return state == State.PLAYING or state == State.PREPARING


func menu_open() -> bool:
    return not field_active()


## The state a new run starts in.
func _run_start_state() -> int:
    return State.PREPARING if build_mode else State.PLAYING


func _go(to: int, request: String) -> void:
    _seq += 1
    transitions.append({"seq": _seq, "from": STATE_NAMES[state], "to": STATE_NAMES[to], "request": request})
    state = to


func _refuse(request: String) -> String:
    _seq += 1
    refused.append({"seq": _seq, "state": STATE_NAMES[state], "request": request})
    return ACT_NONE


## Enter bypass mode: no menus, battle runs immediately (perf / capture / tools).
func start_bypass() -> void:
    bypass = true
    state = State.PLAYING


# --------------------------------------------------------------- requests ---
# Each returns the action the scene must perform (ACT_*) or ACT_NONE when
# the request was refused in the current state.

func start_game() -> String:
    if state != State.TITLE:
        return _refuse("start_game")
    _go(_run_start_state(), "start_game")
    return ACT_NEW_RUN


## WP-008: the one "방어 시작" of a build-mode run. Refused anywhere but
## PREPARING, so a double click / key repeat starts the waves exactly once.
func begin_defense() -> String:
    if state != State.PREPARING:
        return _refuse("begin_defense")
    _go(State.PLAYING, "begin_defense")
    return ACT_BEGIN_DEFENSE


func pause() -> String:
    if not field_active():
        return _refuse("pause")
    pause_return = state
    _go(State.PAUSED, "pause")
    return ACT_NONE


func resume() -> String:
    if state != State.PAUSED:
        return _refuse("resume")
    _go(pause_return, "resume")
    return ACT_NONE


## Settings can be opened from TITLE and PAUSED; opening them while PLAYING
## pauses first (the return target is PAUSED, never PLAYING).
func open_settings() -> String:
    match state:
        State.TITLE:
            settings_return = State.TITLE
            _go(State.SETTINGS, "open_settings")
        State.PAUSED:
            settings_return = State.PAUSED
            _go(State.SETTINGS, "open_settings")
        State.PLAYING, State.PREPARING:
            pause_return = state
            _go(State.PAUSED, "open_settings(pause first)")
            settings_return = State.PAUSED
            _go(State.SETTINGS, "open_settings")
        _:
            return _refuse("open_settings")
    return ACT_NONE


func close_settings() -> String:
    if state != State.SETTINGS:
        return _refuse("close_settings")
    _go(settings_return, "close_settings")
    return ACT_NONE


## R while playing / "다시 시작" while paused -> confirmation. In RESULT the
## restart is immediate (no confirmation, D-040).
func request_restart() -> String:
    match state:
        State.PLAYING, State.PAUSED, State.PREPARING:
            confirm_return = state
            confirm_kind = CONFIRM_RESTART
            _go(State.CONFIRM, "request_restart")
            return ACT_NONE
        State.RESULT:
            result = {}
            _go(_run_start_state(), "result_restart")
            return ACT_NEW_RUN
        _:
            return _refuse("request_restart")


func request_to_title() -> String:
    match state:
        State.PAUSED:
            confirm_return = state
            confirm_kind = CONFIRM_TO_TITLE
            _go(State.CONFIRM, "request_to_title")
            return ACT_NONE
        State.RESULT:
            result = {}
            _go(State.TITLE, "result_to_title")
            return ACT_TO_TITLE
        _:
            return _refuse("request_to_title")


func confirm() -> String:
    if state != State.CONFIRM:
        return _refuse("confirm")
    if confirm_kind == CONFIRM_RESTART:
        confirm_kind = ""
        _go(_run_start_state(), "confirm_restart")
        return ACT_NEW_RUN
    confirm_kind = ""
    _go(State.TITLE, "confirm_to_title")
    return ACT_TO_TITLE


func cancel_confirm() -> String:
    if state != State.CONFIRM:
        return _refuse("cancel_confirm")
    confirm_kind = ""
    _go(confirm_return, "cancel_confirm")
    return ACT_NONE


## Esc: closes exactly one level. TITLE / RESULT ignore it (no quit, no restart).
func back() -> String:
    match state:
        State.PLAYING, State.PREPARING:
            return pause()
        State.PAUSED:
            return resume()
        State.SETTINGS:
            return close_settings()
        State.CONFIRM:
            return cancel_confirm()
        _:
            return _refuse("back")


func quit_from_title() -> String:
    if state != State.TITLE:
        return _refuse("quit")
    _go(State.TITLE, "quit")
    return ACT_QUIT


## The run reached WON / LOST. Only possible while PLAYING (the battle does
## not tick in any other state). The frozen result model is stored here.
func run_ended(model: Dictionary) -> bool:
    if state != State.PLAYING:
        _refuse("run_ended")
        return false
    result = model.duplicate(true)
    _go(State.RESULT, "run_ended")
    return true


func confirm_text() -> Dictionary:
    return CONFIRM_TEXT.get(confirm_kind, {"text": "", "ok": "확인", "cancel": "취소"})


func snapshot() -> Dictionary:
    return {
        "state": state_name(),
        "settings_return": STATE_NAMES[settings_return],
        "confirm_return": STATE_NAMES[confirm_return],
        "confirm_kind": confirm_kind,
        "pause_return": STATE_NAMES[pause_return],
        "build_mode": build_mode,
        "bypass": bypass,
        "has_result": not result.is_empty(),
        "transitions": transitions.duplicate(true),
        "refused": refused.duplicate(true),
    }
