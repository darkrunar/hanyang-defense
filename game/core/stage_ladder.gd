extends RefCounted
## Core-loop expansion ladder (docs/CORE_LOOP_STAGES.md, D-056): the core loop
## split into one-content steps in the order they build on each other, each
## with a test mode (`--stage=N`). A stage is DATA only: which existing preset
## it starts from, which config keys it overrides, which player commands the
## scene lets through, and what to look at. No game rule lives here; every
## stage runs the rules an approved WP already defines.
##
## Stages 1..8 are playable (their content exists). 9.. are the planned
## continuation (DRAFT / candidate WPs): listed so the order is visible, never
## launchable.

const Config := preload("res://game/core/config.gd")
const Placement := preload("res://game/core/placement.gd")

const J: int = Placement.Kind.JANGSEUNG
const H: int = Placement.Kind.HWACHA
const B: int = Placement.Kind.BONGSU
const S: int = Placement.Kind.SENSOR

## preset: "sandbox" = Config.new(), "wp001" = Config.for_wp001(),
##         "wp003" = Config.for_wp003(), "wp008" = Config.for_wp008()
## kinds: structure kinds the player may place / remove in a sandbox stage
##        (waves stages follow their WP's own command rules instead)
## menus: false = the run starts at once (no title / result screen);
##        true = the normal launch flow (TITLE -> run -> RESULT -> restart)
const STAGES: Array = [
    {
        "id": 1, "key": "flow", "title": "적 흐름", "wp": "WP-001",
        "adds": "적 1,000체 · 세 진입로(남대문·서대문·동대문) · 목표 도달(누수)",
        "verb": "관찰",
        "preset": "wp001", "overrides": {"fixture": "none", "combat_enabled": false},
        "kinds": [], "toggle": false, "combat_toggle": false, "menus": false,
        "observe": "세 길로 흐르는 적과 경로별 생존·누수 수(HUD)",
        "check": "30 s: 세 경로 모두 생존 > 0, 누수 > 0, 처치 0, 시설 0",
    },
    {
        "id": 2, "key": "jangseung", "title": "장승 — 길 막기", "wp": "WP-001",
        "adds": "장승 설치(1 + LMB)·철거(RMB): 통행 차단, 모든 길을 막는 자리는 거절",
        "verb": "길을 막아 흐름을 바꾼다",
        "preset": "wp001", "overrides": {"fixture": "none", "combat_enabled": false},
        "kinds": [J], "toggle": false, "combat_toggle": false, "menus": false,
        "observe": "남문 서편 골목 (44,36)에 장승 → 서편 골목 비고 동편 골목으로 우회",
        "check": "같은 시드 35 s: 장승 없음 대비 서편 골목 밀도 0, 동편 증가, 두 골목 동시 차단은 거절",
    },
    {
        "id": 3, "key": "hwacha", "title": "화차 — 집중 사격", "wp": "WP-001",
        "adds": "화차 4대(설치 2 + LMB): 사거리 안 가장 밀집한 존에 광역 사격",
        "verb": "병목을 만들고 화력을 모은다",
        "preset": "wp001", "overrides": {},
        "kinds": [J, H], "toggle": false, "combat_toggle": true, "menus": false,
        "observe": "장승으로 한 골목에 몰면 같은 화차의 처치가 는다 (Z 밀도 존, G 사거리)",
        "check": "같은 시드: 1단계 대비 누수 감소, 장승 병목 시 화차·중영 처치 증가",
    },
    {
        "id": 4, "key": "network", "title": "봉수망 — 탐지 공유", "wp": "WP-002",
        "adds": "봉수대 8·혼천의 4: 화차는 자기 100 px만 보고, 같은 망의 혼천의가 본 적을 공유받아 쏜다",
        "verb": "연결해서 먼 적을 쏘게 한다",
        "preset": "sandbox", "overrides": {},
        "kinds": [J, H, B, S], "toggle": true, "combat_toggle": true, "menus": false,
        "observe": "봉수 B8을 T로 끄면 남쪽 혼천의 공유가 끊겨 공유 사격이 멈춘다 (커서 정보 패널)",
        "check": "20 s: 공유 전용 사격 > 0, 봉수대 전부 끄면 공유 전용 사격 0",
    },
    {
        "id": 5, "key": "waves", "title": "웨이브·거점 방어", "wp": "WP-003",
        "adds": "유한 3웨이브 1,140체 · 외곽 거점 HP 360 · 핵심 HP 60 · 승리",
        "verb": "관찰 (WP-003 계약: 자유 설치 없음)",
        "preset": "wp003", "overrides": {},
        "kinds": [], "toggle": false, "combat_toggle": false, "menus": false,
        "observe": "웨이브 W1→W3, 외곽 거점 HP가 도달만큼 깎이고 전부 해소되면 승리",
        "check": "입력 없이 끝까지: WON, 붕괴 0, 1,140체 생성, 외곽 HP > 0",
    },
    {
        "id": 6, "key": "collapse", "title": "붕괴·후퇴·회수", "wp": "WP-003",
        "adds": "외곽 HP 0 → 붕괴: 외곽 시설 소등, 목표가 핵심으로, 화차·중영 회수 → 내곽 재배치(LMB)",
        "verb": "무너진 뒤 남은 화력을 안쪽에 다시 놓는다",
        "preset": "wp003", "overrides": {"outer_hp": 40.0},
        "kinds": [], "toggle": false, "combat_toggle": false, "menus": false,
        "observe": "외곽 HP 40(빠른 붕괴, 실제 도달) → 노란 내곽의 빈 칸 클릭으로 회수 화차 배치",
        "check": "강제 없이 붕괴 1회, 회수 배치 B ok(같은 ID), 런 종료까지 진행",
    },
    {
        "id": 7, "key": "loop", "title": "반복 플레이 — 시작·결과·재시작", "wp": "WP-004",
        "adds": "시작 화면·일시정지·설정·결과 장부·같은 시드 즉시 재시작",
        "verb": "결과를 보고 같은 조건으로 다시 시도한다",
        "preset": "wp003", "overrides": {},
        "kinds": [], "toggle": false, "combat_toggle": false, "menus": true,
        "observe": "게임 시작 → 전투 → 결과 화면의 처치·도달·붕괴·회수·핵심 HP → R 재시작",
        "check": "TITLE → PLAYING → RESULT → R → 새 런(run_id +1, 같은 초기 상태)",
    },
    {
        "id": 8, "key": "build", "title": "준비·건설·물자", "wp": "WP-008",
        "adds": "준비 단계 · 물자 240(처치 +1, 웨이브 +80) · 유료 건설 1~4 · 붕괴 후 내곽 증설",
        "verb": "벌어서 짓고, 무너지면 안쪽에 다시 짓는다",
        "preset": "wp008", "overrides": {},
        "kinds": [J, H, B, S], "toggle": false, "combat_toggle": false, "menus": true,
        "observe": "준비 단계에서 1~4로 고르고 빈 칸 클릭(비용·잔액 고스트) → Space 방어 시작",
        "check": "TITLE → PREPARING(시간 정지) → 방어 시작 → 구매 1클릭 1개, 장부 불변식",
    },
]

## The planned continuation. Order after 10 is a candidate list, not a plan.
const PLANNED: Array = [
    {"id": 9, "key": "gate", "title": "성밖 접근·성문 공방", "wp": "WP-009 (DRAFT)",
        "adds": "넓은 성밖 집결·접근 예고·성문 HP/공격/파괴·통로 개방"},
    {"id": 10, "key": "siege", "title": "공성 적·장승 파괴", "wp": "WP-010 (DRAFT)",
        "adds": "일반 적 우회 + 공성 적의 장승 공격, 파괴 뒤 경로 재계산"},
    {"id": 11, "key": "character", "title": "캐릭터 현장 개입(포졸·사또)", "wp": "후보 (WP 없음)",
        "adds": "유도·포박·차단·수리 (CORE_LOOP C 단계)"},
    {"id": 12, "key": "resources", "title": "정보·혼 · 런 성장", "wp": "후보 (WP 없음)",
        "adds": "추가 자원, 시설 해금·융합, 보스"},
    {"id": 13, "key": "meta", "title": "규장각 메타 성장", "wp": "후보 (WP 없음)",
        "adds": "런 사이 기록·전략 해금"},
]


static func count() -> int:
    return STAGES.size()


static func is_playable(id: int) -> bool:
    return id >= 1 and id <= STAGES.size()


static func get_stage(id: int) -> Dictionary:
    if not is_playable(id):
        return {}
    return STAGES[id - 1]


static func planned(id: int) -> Dictionary:
    for p: Dictionary in PLANNED:
        if int(p["id"]) == id:
            return p
    return {}


## Stage id from "3", "hwacha" or "stage3"; -1 when unknown.
static func parse(arg: String) -> int:
    var a: String = arg.strip_edges().to_lower().trim_prefix("stage")
    if a.is_valid_int():
        return int(a)
    for s: Dictionary in STAGES:
        if s["key"] == a:
            return int(s["id"])
    for p: Dictionary in PLANNED:
        if p["key"] == a:
            return int(p["id"])
    return -1


## The stage's configuration: its preset plus its overrides.
static func config_for(id: int) -> Config:
    var st: Dictionary = get_stage(id)
    var c: Config
    match str(st.get("preset", "sandbox")):
        "wp001": c = Config.for_wp001()
        "wp003": c = Config.for_wp003()
        "wp008": c = Config.for_wp008()
        _: c = Config.new()
    var ov: Dictionary = st.get("overrides", {})
    for k: String in ov:
        c.values[k] = ov[k]
    return c


static func allows_kind(id: int, kind: int) -> bool:
    return (get_stage(id).get("kinds", []) as Array).has(kind)


## The stage that first adds `kind` as a player command (for refusal hints).
static func stage_adding_kind(kind: int) -> int:
    for s: Dictionary in STAGES:
        if (s["kinds"] as Array).has(kind):
            return int(s["id"])
    return -1
