# WP-004 Result

- 작성일: 2026-09-16
- WP / 상태: WP-004 플레이 흐름·메뉴·재시작 / **REVIEW** (GPT 판정 PENDING)
- 기준 커밋: `d3bd9d8` ("docs(wp-004): define play flow menus restart and settings acceptance criteria", main, READY v1.0)
- 검증한 구현 커밋: **`d63b9b7`** ("feat(wp-004): play flow …") → `90090ce`(uid·verify 스위치) → **`e715906`**(TITLE에서 연 설정 화면 뒤 HUD 숨김; 최종 게임 트리) → `96ec3c9`(verify 스크립트만). 성능 manifest `implementation_sha` = `96ec3c9`(게임 트리 = `e715906`). 결과·증거 커밋: 이 문서의 커밋(별도 문서 커밋으로 자기참조 회피).
- 브랜치: `wp/004-play-flow` · PR: https://github.com/darkrunar/hanyang-defense/pull/6 (Draft, 병합 금지)
- 실행 환경 / 엔진·버전: Godot 4.7.stable.official.5b4e0cb0f (GDScript, 2D, gl_compatibility) · Windows 11 Home 10.0.26200 · AMD Ryzen 5 7600 · NVIDIA GeForce RTX 4070 SUPER · 63.2 GB · 1920×1080 창(캡처는 1280×720도) · vsync off · Parsec 가상 디스플레이 어댑터 공존

이 문서는 `results/RESULT_TEMPLATE.md` 양식을 따른다. 수치는 `results/evidence/wp-004/` 원시 파일에서 가져왔고, 승인된 WP-001/002/003 증거는 건드리지 않았다(`verify.ps1 -Wp004`). WP-003의 전투 규칙·밸런스(HP 360/60·18시설·10존·1,140체·회수 규칙·승패 우선순위)는 바꾸지 않았다.

## 구현 결과

계약은 [backlog/WP-004.md](../backlog/WP-004.md) READY v1.0(D-039~042)이다. 구현자가 정한 자료구조·경계는 D-043~046에 기록했다.

| 파일 | 목적 |
|---|---|
| `game/core/play_flow.gd` (신규) | UI 상태 기계 TITLE/PLAYING/PAUSED/SETTINGS/CONFIRM/RESULT. 복귀 대상(설정→들어온 곳, 확인창→PLAYING 또는 PAUSED), 확인 문구·버튼 라벨, Esc 한 단계 닫기, RESULT의 즉시 재시작/시작 화면, TITLE만 종료. 전이·거절 로그(순번). RunState와 분리 |
| `game/core/result_model.gd` (신규) | 종료 시 1회 확정하는 결과 모델: 승패(RunState), 플레이 시간 mm:ss(전투 시뮬레이션 시간, 초 미만 버림), 도달 웨이브(1부터), 처치(killed_total), 외곽/핵심 도달(arrivals), 외곽 유지/붕괴·mm:ss, 회수 없음/회수 후 미배치/재배치 완료, 재배치 셀·월드 좌표, 핵심/외곽 HP·최대. 표시 행 생성 |
| `game/core/user_settings.gd` (신규) | 창 모드/전체화면 설정 ConfigFile 저장·로드, 경로 주입, 누락/파싱 오류/범위 밖 → 기본값, 저장 실패 보고 |
| `game/scenes/menu_layer.gd` (신규) | TITLE/PAUSED/SETTINGS/CONFIRM/RESULT 패널(실제 Button 노드, 전체 화면 dim이 클릭 소비, 기본 포커스, 결과 미니맵 마커), 상태별 표시·라벨·알림 |
| `game/scenes/main.gd` | 일반 실행 TITLE 시작·설정 로드(검증 모드는 우회·미로드), 의도 큐(프레임 시작 적용, stale 폐기), PLAYING에서만 전투 틱·홀드 재시도, 런 종료 → 결과 모델 확정 → RESULT, 새 런/시작 화면 복귀(battle.restart + 입력 초기화), Esc/P 일시정지·R 확인창·RESULT R 즉시, 우상단 일시정지 버튼, `--settings=`, 캡처 `wp004_ui`/`wp004_ui_720`(실제 버튼·키 스텝, 상태 로그, 검증 전용 강제 붕괴/패배) |
| `tests/test_play_flow.gd` (신규), `tests/run_tests.gd`, `tests/test_scene_modes.gd` | AC-01~08을 실제 scene(버튼 `pressed` 신호·합성 키/마우스 이벤트·물리 프레임)으로 검증. R-03 시험은 확인창 흐름으로 갱신 |
| `scripts/verify.ps1`, `verify.sh` | 4d WP-004 캡처 2종 + 상태 전이 로그 검사, `-Wp004`(WP-004 캡처·새 release collapse 성능을 `wp-004/`에, 승인 증거 보존) |
| `README.md`, `docs/GAME_GUIDE.md`, `docs/DECISIONS.md`, `backlog/WP-004.md`, `docs/ROADMAP.md` | 흐름·조작·설정 안내, D-043~046, 상태 REVIEW |

## 실행·재현 절차

필요 도구: Godot 4.7.stable(`godot` PATH), Windows export template(빌드·성능), PowerShell(성능 샘플러). 추가 패키지 없음.

```bash
git clone https://github.com/darkrunar/hanyang-defense.git && cd hanyang-defense && git checkout wp/004-play-flow
```

| 단계 | 명령 | 산출물 |
|---|---|---|
| 자동 검증(회귀 780 + WP-004) | `godot --headless --path . --script res://tests/run_tests.gd -- --report=<abs>/results/evidence/wp-004/tests/test_report.txt` | **1,053 passed / 0 failed (52 s; 기존 780 + WP-004 스위트 12케이스 267체크 + scene R-03 갱신분)**, 종료 0 |
| 메뉴 흐름 캡처 | `godot --path . --rendering-driver opengl3 -- --capture=wp004_ui --out-dir=<abs>/results/evidence/wp-004/captures --settings=<abs>/…/settings_capture.cfg` (`wp004_ui_720`도 동일) | PNG 11장 × 2 해상도 + `wp004_ui*_log.json`(상태 전이·버튼·키·결과 모델·flow 스냅샷) |
| 릴리스 빌드 | `godot --headless --path . --export-release "Windows Desktop Release" build_out/windows/hanyang_defense_wp001.exe` | exe |
| 전환 성능(새 빌드) | `.\scripts\perf_with_memory.ps1 -Scenario collapse_move\|collapse_combat -Warmup 10 -Measure 60 -Out results\evidence\wp-004\perf\perf_<sc>_1000_release.json` | 원시 배열·구간·이벤트·manifest·exe 해시 |
| 일괄 | `.\scripts\verify.ps1 -Wp004` | 위 전부, 계약 검사 포함, 종료 0 |
| 플레이 | `godot --path . --rendering-driver opengl3` | 시작 화면부터. 조작은 README / GAME_GUIDE 9절 |

설정: 시드 20260913, 60 Hz 고정, WP-003 계약값 그대로. 캡처는 `--settings`로 임시 파일을 주입해 실제 사용자 설정을 건드리지 않고, 20 s 강제 붕괴·핵심 HP 1 강제(검증 전용, 로그에 `forced_hp_writes`)로 패배·승리 결과를 빠르게 만든다. 이 강제 훅은 메뉴에 노출되지 않는다.

## Acceptance Criteria

| AC | PASS / FAIL / NOT RUN | 기대 결과 | 실제 결과 | 증거 파일·로그·화면 |
|---|---|---|---|---|
| AC-01 | **PASS** | TITLE→전투→RESULT→재시작/시작 화면, 실제 버튼으로 새 런; F1 승리·F2 재편 승리·F4 패배 재현 | 게임 시작 버튼 → PLAYING(첫 프레임 1틱). F1(입력 없음, HP 360) → **WON 01:39**, 외곽 유지, 회수 없음, 처치 826·외곽 도달 314 → RESULT 자동. 다시 시작 버튼 → 확인 없이 PLAYING, run_id+1, 이전 결과 폐기. F2(20 s 강제 붕괴, 실제 클릭으로 B 배치) → WON, 재배치 완료 (44,13), "외곽 붕괴 · 00:20". F4(핵심 HP 1 + 마지막 도달) → LOST, 핵심 0 → 시작 화면으로 버튼 → TITLE(초기 전장), 다시 게임 시작은 새 run_id | `test_report.txt` "AC-01"; 캡처 `wp004_ui_03/09/10/11`, 로그 `wait_result` 2건(LOST 00:26 → WON 01:45) |
| AC-02 | **PASS** | PAUSED/SETTINGS/CONFIRM 각 120틱 동안 전투 구조화 상태 불변·배치 0, 재개 후 몰아 처리 없음 | 적 이동 중·H1 회수 대기 상태에서 세 화면 각각 120 프레임: `full_state_json` 동일, 틱 0, 명령 0(홀드 클릭 포함), 회수권 1 유지. 계속하기 프레임에 정확히 1틱, 이후 프레임당 1틱, sim_time 6틱분만 증가 | 테스트 "AC-02" |
| AC-03 | **PASS** | R/다시 시작 확인·취소 정확, RESULT는 확인 없이 1회 | PLAYING R → CONFIRM("다시 시작"/"취소"), 10프레임 전투 불변, 취소 → PLAYING 같은 run; 확인 → 새 런 정확히 1회(전이 로그 1건). PAUSED 다시 시작/시작 화면으로 → CONFIRM, 취소 → PAUSED 유지, 확인 → TITLE 1회. RESULT 다시 시작 더블클릭 → 새 런 1회, 두 번째 클릭 stale 폐기 | 테스트 "AC-03"; 캡처 06/07/08, 로그 `button`/`key` state_before→after |
| AC-04 | **PASS** | 새 런 = WP-003 초기 상태(run_id 제외), 이전 입력 무효 | 진행 중(홀드 클릭 중)·LOST 후·WON 후 재시작 각각 `full_state_json` == 새 Battle을 같은 틱만큼 진행한 상태; 회수권 0·대기 0·강제 HP 기록 0; 확인창 진입 시 홀드 폐기. 런 종료 후 남아 있던 pause/restart 의도 2건 → stale 폐기, RESULT 유지, 자동 새 런 없음 | 테스트 "AC-04" |
| AC-05 | **PASS** | Esc 계층·메뉴 입력 소비·종료 우선순위 | TITLE Esc 무시(종료 아님), PLAYING Esc→PAUSED, 설정 Esc→PAUSED(한 단계), PAUSED Esc→PLAYING, CONFIRM Esc→취소만, SETTINGS/CONFIRM의 R·P 무시, RESULT Esc 무시. 메뉴 중 LMB press 소비(`_mouse_down` false), 재개 후 release는 명령 0, 새 press만 배치 1회 | 테스트 "AC-05"; 캡처 로그 `key` 7건 |
| AC-06 | **PASS** | 결과 수치 = 실제 장부, 종료 후 불변, pause 제외, 미배치 표시 | 120프레임 일시정지 후 종료한 런: play_time == RunState.end_sim_time == 틱×dt(일시정지 제외), mm:ss, 웨이브 1-based, 처치/도달/붕괴 시각/회수 상태/핵심 HP 전부 장부와 일치, 미배치 "—". RESULT 120프레임 후 결과 JSON·전투 상태 동일 | 테스트 "AC-06", "ResultModel unit"; 캡처 로그 `result` |
| AC-07 | **PASS** | 창/전체화면 적용·재실행 유지·손상 복구·저장 실패 알림; 두 해상도 캡처 겹침 없음 | 설정 토글 → 즉시 저장·라벨 갱신, TITLE/PAUSED 동일 값, 새 scene(재실행) fullscreen 유지, 손상/범위 밖 파일 → 기본값·실행 계속, 쓸 수 없는 경로 → "설정 저장 실패" 알림·세션 내 값 유지. 캡처 1920×1080·1280×720 각 11장: TITLE/SETTINGS(2)/PLAYING/PAUSED/CONFIRM(3)/RESULT(2)/TITLE — 한글·포커스·버튼 겹침 없음, 메뉴 닫힘 후 HUD 배치 복원 | 테스트 "UserSettings unit", "AC-07"; `captures/wp004_ui_*.png`, `wp004_ui_720_*.png` |
| AC-08 | **PASS** | 기존 회귀 종료 0, legacy 8존/WP-003 10존·자동 모드 메뉴 우회, 새 release collapse 성능 계약 | 전체 1,053 passed / 0 failed (52 s; 기존 780 + WP-004 스위트 12케이스 267체크 + scene R-03 갱신분) 종료 0(기존 780건 포함). `--perf`/`--capture=ac02`는 bypass·설정 미로드·즉시 PLAYING, 존 10/8 확인; `wp004_ui`만 TITLE. 새 release(`96ec3c9 = 게임 트리 e715906`) 성능: collapse_move **221.1 FPS / p95 12.60 ms**, collapse_combat **250.2 FPS / p95 11.51 ms**, 전 프레임 alive ≥1000, 6 이벤트, 배치 ok, 구간 합 = 전체 프레임, exe SHA-256 일치 (WP-003 회차 4와 동급) | 테스트 "AC-08", "WP-003 scene entry paths"; `wp-004/perf/*.json` |

자동 검증 합계: **1,053 passed / 0 failed (52 s; 기존 780 + WP-004 스위트 12케이스 267체크 + scene R-03 갱신분)**, 종료 코드 0.

## 성능

- OS / CPU / GPU / RAM / 해상도 / 빌드 설정: 위 실행 환경. exported release, gl_compatibility, 1920×1080, vsync 0. 실행파일 SHA-256 `134ffed4b8d215c6509ec90b757a5e7fb44215bab09dcfebb77b9371f6fa6783`(게임 자체 기록 = 외부 Get-FileHash).
- 시나리오: WP-003 D-027 그대로(fixture C 18시설·10존·`benchmark_hold_alive`·외곽 HP 1e6 → 측정 20 s 트리거·25 s 배치 B·핵심 무적 집계). 메뉴는 bypass(manifest `flow.bypass`가 아니라 `--perf` 경로 자체가 TITLE을 만들지 않음; 테스트 AC-08).

| 시나리오 | 프레임 / 초 | 생존 min / avg / max | 평균 FPS | 프레임 ms p50 / **p95** / p99 / max | 구간 [0,20) / [20,25) / [25,60] avg FPS · p95 | 구간 합 = 전체 | 이벤트·전환 | 워킹셋 MB |
|---|---|---|---|---|---|---|---|---|
| collapse_move | 13,264 / 60.00 | 1000 / 1000.0 / 1001 | **221.1** | 2.71 / **12.60** / 16.28 / 28.97 | 169.7·15.46 / 270.1·11.43 / 243.4·12.12 (3,394 + 1,349 + 8,521) | 13,264 = 13,264 | 6건 tick 1805 + recovery_placed 2105, 트리거→붕괴 0틱, 배치 ok, pv 4→5, 핵심 흡수 2,072 | 188.2→191.2 |
| collapse_combat | 15,011 / 60.00 | 1000 / 1000.0 / 1001 | **250.2** | 2.48 / **11.51** / 13.78 / 52.50 | 210.9·13.04 / 273.8·11.28 / 269.2·11.05 (4,218 + 1,370 + 9,423) | 15,011 = 15,011 | 6건 tick 1805 + recovery_placed 2106, 배치 ok, pv 4→5, H1 배치 후 42발, 핵심 흡수 5 | 183.1→187.8 |

- 예산(D-009 평균 ≥60 FPS·p95 ≤25 ms·전 프레임 alive ≥1000)과 D-027(6 이벤트·트리거→붕괴 ≤2틱·배치 ok·pv 기대+1·구간 평가 >0), R-05 검사(구간 완전 매핑·manifest 존 10/시설 18·exe 해시) 모두 통과. WP-003 회차 4(221.5 / 247.3 FPS)와 같은 수준이다.

## 실제 화면 확인

`--capture=wp004_ui`(1920×1080)와 `wp004_ui_720`(1280×720)가 같은 스크립트를 실제 버튼(`pressed` 신호)과 키 이벤트로 재생한다. 각 PNG와 같은 시각의 로그가 `wp004_ui*_log.json`에 있다.

| 캡처 | 관측 |
|---|---|
| `01_title` | 시작 화면: 제목·소개·게임 시작(포커스, 주황)·설정·종료. 배경은 정적인 초기 전장, HUD 숨김 |
| `02_settings_from_title` | 설정: 화면 "창 모드" 버튼·안내·뒤로. Esc → TITLE(로그 `settings_esc_returns_to_title`) |
| `03_playing_t12` | 전투 12 s: 기존 HUD 두 패널 + 우상단 일시정지 버튼, 메뉴 없음 |
| `04_paused` | Esc → 일시정지 메뉴(계속하기 포커스), HUD "[일시정지]", 전장 정지 |
| `05_settings_from_pause` | 일시정지 → 설정. Esc → PAUSED(한 단계) |
| `06_confirm_restart` | 다시 시작 → 확인창 "현재 전투를 종료하고 처음부터 시작할까요?" 취소(포커스)/다시 시작. 취소 → PAUSED |
| `07_confirm_to_title` | 시작 화면으로 → 확인창(진행 상황 미저장 문구). Esc → 취소만(PAUSED), 다시 Esc → 전투 재개 |
| `08_confirm_from_r_after_collapse` | 붕괴 뒤 전투 중 R → 확인창(전투 정지). 취소 → PLAYING |
| `09_result_lost` | 핵심 HP 1 + 도달 → 결과: 패배, 00:26, 웨이브 1/3, 회수 후 미배치, 재배치 위치 —, 핵심 0/60 |
| `10_result_won` | R로 즉시 재시작 → 20 s 강제 붕괴 → 25 s B 배치 → 승리 01:45, 3/3, 처치 1073, 도달 외곽 36·핵심 32, 외곽 붕괴 · 00:20, 재배치 완료 (44,13)(미니맵 마커), 핵심 28/60 |
| `11_title_again` | 시작 화면으로 → 확인 없이 TITLE, 초기 전장 |

1280×720에서도 같은 배치가 축소되어 글자·버튼·포커스가 잘리거나 겹치지 않는다(캡처 `wp004_ui_720_*`).

## 미해결 문제와 설계 변경 제안

1. 결과 미니맵은 192×108 축소 사각형에 내곽·두 거점·재배치 마커만 그린다. 전장 그림 축소판은 후속 시각 작업이다.
2. 전체화면 전환은 실제 창에서만 동작하며 헤드리스 검증은 설정값 저장·복구·라벨까지만 확인했다(실제 창 모드 전환은 수동 확인).
3. 게임패드·런 저장·통계 누적은 Non-Goals대로 미구현이다. 일시정지 중 메뉴 애니메이션은 없다(정적 패널).
4. 이전 WP의 미측정 항목(프레임 시간 이봉 분포, 단발 스파이크)은 그대로다.

## 다음 WP 영향

- `PlayFlow`는 상태 추가(예: 상점/업그레이드 화면)를 전이 표에 더하면 되고, `ResultModel`은 경제 WP의 보상 계산 입력이 될 수 있다. `UserSettings`는 음량 등 실제 기능이 생길 때 키를 추가한다.
- 의도 큐(D-044)는 모든 UI 요청의 단일 진입점이므로 후속 UI도 같은 경로를 써야 stale/중복 규칙이 유지된다.

## PR

- Draft PR #6: https://github.com/darkrunar/hanyang-defense/pull/6 · 구현 `d63b9b7`→`e715906` · 결과·증거 `f0bf6b6`

## GPT Review

- 검토일 / 검토한 구현 커밋: (PENDING) / `e715906` (구현 `d63b9b7` → `e715906`; 리뷰 대상 diff `d3bd9d8..HEAD`)
- 최종 판정: **PENDING**
- 기준별 검토 결과: (PENDING)
- 범위 준수 / 기획 일치 / 증거 충분성: (PENDING)
- 보완 요청 또는 다음 WP 준비 사항: (PENDING)

이 문서는 구현·테스트 결과 기록이며, DONE 전환은 모든 필수 AC 충족과 GPT PASS 이후에만 한다.
