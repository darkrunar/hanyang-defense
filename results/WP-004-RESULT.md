# WP-004 Result

- 작성일: 2026-09-16
- WP / 상태: WP-004 플레이 흐름·메뉴·재시작 / **REVIEW** (GPT 1차 REVISE 2026-09-19 → 보완 회차 1 `a24e3fe`, 재리뷰 대기)
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
| AC-05 | **PASS** (1차 리뷰 FAIL → 보완 회차 1에서 해소) | Esc 계층·메뉴 입력 소비·종료 우선순위·닫기 입력 해제 경계 | TITLE Esc 무시(종료 아님), PLAYING Esc→PAUSED, 설정 Esc→PAUSED(한 단계), PAUSED Esc→PLAYING, CONFIRM Esc→취소만, SETTINGS/CONFIRM의 R·P 무시, RESULT Esc 무시. 메뉴 중 LMB press 소비(`_mouse_down` false), 재개 후 release는 명령 0. **메뉴를 닫은 입력을 떼기 전 press는 거절(명령 0·회수권 유지·재시도 없음), 뗀 뒤 새 press만 배치 1회** — Esc/Enter/닫기 클릭/RESULT R, 직접 핸들러와 Viewport 경로 | 테스트 "AC-05", "AC-05 R-01 release fence", "AC-05 run already LOST…"; 캡처 로그 `key`·`fence_probe` |
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

- Draft PR #6: https://github.com/darkrunar/hanyang-defense/pull/6 · 구현 `d63b9b7`→`e715906` · 결과·증거 `f0bf6b6` · GPT 1차 리뷰 REVISE `0f1f166` · 보완 회차 1 `a24e3fe`

## GPT Review

- 검토일 / 검토한 구현 커밋: (PENDING) / `e715906` (구현 `d63b9b7` → `e715906`; 리뷰 대상 diff `d3bd9d8..HEAD`)
- 최종 판정: **PENDING**
- 기준별 검토 결과: (PENDING)
- 범위 준수 / 기획 일치 / 증거 충분성: (PENDING)
- 보완 요청 또는 다음 WP 준비 사항: (PENDING)

이 문서는 구현·테스트 결과 기록이며, DONE 전환은 모든 필수 AC 충족과 GPT PASS 이후에만 한다.

### 2026-09-19 — GPT Review / PR #6

- 최종 판정: **REVISE**. AC-05 입력 해제 경계가 충족되지 않았다. WP-004는 REVIEW를 유지한다.
- 검토 범위: `d3bd9d8..9a6fc943bcf3218f46a50918d1e2cfccc0f9d370`. 구현 GDScript는 `e715906`, 성능 manifest는 `96ec3c9f631bac32c314afe42c6f0fcbd08b8103`. manifest 커밋 이후 게임 경로 차이는 UID 메타데이터 추가이며 GDScript 변경은 없다.
- 독립 재실행: Godot 4.7.stable.official.5b4e0cb0f, **1,053 PASS / 0 FAIL, 55.0초, 종료 코드 0**. 추가 입력 재현은 직접 핸들러와 Viewport 입력 전달 양쪽에서 실패를 확인했다.
- 리뷰 증거: `results/evidence/wp-004/gpt-review/2026-09-19/`의 `test_report.txt`, `review_input.gd`, `input_review.json`, `audit_perf.ps1`, `perf_audit.json`.

| AC | GPT 판정 | 근거와 범위 |
|---|---|---|
| AC-01 | PASS | 재실행 F1 정상 승리 / F2 재편 승리 / F4 패배, RESULT 자동 진입, 실제 Button 노드 신호를 통한 재시작·TITLE 복귀 통과. 제출된 승패 캡처·로그와 대조 |
| AC-02 | PASS | 회수 대기·적 이동 상태의 PAUSED / SETTINGS / CONFIRM 각 120 UI 프레임에서 전투 구조화 상태·배치 명령 불변, 재개 후 프레임당 1틱 검증 통과 |
| AC-03 | PASS | PLAYING R·PAUSED 재시작/복귀 확인·취소·원래 상태 복귀 및 RESULT 중복 재시작 1회 통과 |
| AC-04 | PASS | 진행 중 / WON / LOST 이후 동일 시드 새 Battle 상태 비교, run_id 변경, 기존 held 입력 폐기 통과. 메뉴 닫기 키 해제 경계의 결함은 AC-05로 판정 |
| AC-05 | **FAIL** | Esc 계층과 release 이벤트 자체의 배치 방지는 통과하지만, 메뉴를 닫은 Esc를 떼기 전 다른 전장 press를 차단하지 않음. R-01 참조 |
| AC-06 | PASS | 결과 모델의 실제 장부 참조, F1/F2/F4 결과·캡처 로그 대조, 미배치 —, 시뮬레이션 시간, RESULT 120프레임 불변 통과 |
| AC-07 | PASS | 설정 저장/재생성 시 복원·누락/손상/잘못된 값·저장 실패 알림 테스트 통과. 제출된 1080p/720p TITLE·PAUSED·SETTINGS·CONFIRM·RESULT 대표 화면에서 한글·버튼·포커스 잘림/겹침 없음. 실제 OS 전체화면 전환은 구현자의 수동 확인 기록과 DisplayServer 적용 경로를 근거로 하며, 리뷰어의 별도 창 전환 재실행은 NOT RUN |
| AC-08 | PASS | 기존 회귀 포함 1,053건, legacy 8존/WP-003 10존 및 메뉴/사용자 설정 우회 통과. 제출 release 원시 배열 재계산·구간 매핑·6 이벤트·manifest/외부 실행파일 해시 대조 통과 |

#### R-01 [P2, 필수] 메뉴 닫기 입력이 해제되기 전 전장 배치를 막아야 함

- 위치: `game/scenes/main.gd:644` (`_handle_key_event`), 특히 662~672행의 마우스 press 처리. `_clear_field_input`은 기존 홀드를 비우지만, 메뉴를 닫은 키/버튼이 해제됐는지 추적하지 않는다.
- 재현: H1 회수 대기 → Esc로 PAUSED → Esc release → Esc press로 재개 → **두 번째 Esc release 없이** B 위치에서 LMB press. 직접 핸들러 시험 및 `Viewport.push_input`을 사용하는 GUI 입력 경로 시험 모두 **accepted_delta=1, recovery_placed=true**였다. 기대값은 accepted_delta=0이다.
- 영향: 재개 키를 누른 상태에서 클릭하면 WP §2의 입력 잠금이 풀리기 전에 1회뿐인 회수권을 소비한다. 이는 새 배치 검사 규칙 변경 문제가 아니라 메뉴/전장 경계 문제다.
- 수정 요청: 메뉴를 닫는 입력의 release를 확인할 때까지 전장 명령을 막는다. 차단 중 들어온 press를 held 재시도로 넘기지 말고, 닫기 입력 release 이후 새 press에서만 배치한다. Esc 취소/재개뿐 아니라 Enter 및 마우스로 닫는 경로도 같은 계약을 유지한다. D-044의 설명도 이 규칙을 반영한다.
- 재시험: Esc held + LMB, Enter held + LMB, 닫기 클릭의 press/release, 차단 중 누른 LMB를 계속 hold하는 경우, release 후 새 press, 재시작 뒤 지연 입력을 Viewport 입력 경로로 검사한다. release 전 명령/회수권 변화 0, release 후 새 press에서만 1회를 단언하고 전체 회귀를 다시 실행한다.
- 기존 시험 누락 이유: AC-05는 메뉴에서 누른 LMB의 release가 명령을 만들지 않는지만 확인한다. 메뉴를 닫은 Esc 자체를 release하지 않은 채 새 LMB를 넣는 경계를 확인하지 않는다. Button `pressed.emit()`도 실제 버튼 press/release 전달을 대신 검증하지 못한다.

#### 종료 우선순위 경계 관측 — 일반 플레이 결함으로 단정하지 않음

`review_input.gd`의 별도 주입 시험은 pause를 큐에 넣은 뒤 `battle.step`을 직접 호출하여 LOST를 확정하고 scene 프레임을 실행한다. 이때 `_apply_intents`가 먼저 실행되어 UI가 PAUSED에 남는다. 다만 일반 `_physics_process`는 전투 step과 `_check_run_end`를 같은 콜백에서 실행하므로 이번 리뷰에서 이 순서가 정상 사용자 입력만으로 발생하는 경로는 확인하지 못했다. 이 주입 결과를 별도의 배포 차단 결함으로 계산하지 않는다. 후속 비동기 전투/명령 추가 시에는 이미 끝난 RunState를 의도 큐 처리 전에 확인하고, 기존의 '이미 RESULT인 상태에 stale 입력을 추가'하는 시험과 구별하는 것이 좋다.

#### 성능 원시 자료 대조

| 제출 release 자료 | 원시 프레임 수 | 재계산 평균 FPS | 재계산 p95 ms | alive 최솟값 | 판정 |
|---|---:|---:|---:|---:|---|
| collapse_move | 13,264 | 221.06 | 12.600 | 1,000 | PASS |
| collapse_combat | 15,011 | 250.18 | 11.510 | 1,000 | PASS |

각 `frame_us_raw` 합/분위수, `alive_raw`, 구간 인덱스의 연속성·전체 프레임 포함·구간 FPS/p95·후보 평가 증가를 다시 계산했다. 두 manifest 모두 10존/18시설, semantic event 6건, trigger→collapse 0틱, 배치 ok, 경로 버전 시작4→종료5, 실행파일 SHA-256과 외부 메모리 샘플러 기록이 일치한다. 최상위 `path_version_expected=4`는 collapse 증가를 포함하지 않는 기존 필드이므로 D-027의 시작값+1 및 이벤트를 기준으로 판정했다. 이 필드는 후속 정리 시 혼동 없이 표시하는 편이 좋다.

리뷰어는 새 release export/10+60초 성능 측정과 OS 창 전환을 별도로 재실행하지 않았다. 위 성능 PASS는 제출된 release 증거의 독립 재계산 결과다. 화면 검토 역시 제출 PNG와 로그를 근거로 하며 이번 리뷰에서 새 캡처를 만들었다는 의미는 아니다.

#### 기획 판단 / 다음 조치

D-039~042의 동일 전장 재시도, 전투와 UI 상태 분리, 결과 장부, 창 모드만 제공하는 설정 범위는 유지한다. D-043/045/046의 구현 방향은 수용한다. D-044는 R-01의 release 경계를 보완해야 한다. 전장 전체 픽셀아트 교체·음향·재화 기능은 이번 수정에 추가하지 않는다. **R-01 수정과 대응 증거 제출 후 재리뷰**하며, 현재 PR은 병합/DONE 처리하지 않는다.

### 2026-09-19 — 보완 회차 1 (R-01 해제 펜스)

- 보완 커밋: **`a24e3fe`** ("fix(wp-004): release fence …", 게임 트리·테스트·verify). 이 문서와 증거는 별도 문서 커밋. 재리뷰 대상 diff `0f1f166..HEAD`.
- 판정 반영: R-01 [P2, 필수] 수정. 종료 우선순위 경계 관측은 결함으로 계산되지 않았으나 같은 회차에 순서를 고정하고 시험을 추가했다. `path_version_expected` 표시 정리는 이번 수정에 넣지 않았다(성능 manifest 형식은 WP-003 승인 증거와 같게 유지).
- 기획 유지: D-039~042 그대로. 게임 규칙·수치 변경 없음. D-044 마지막 문장을 D-047이 보완.

#### 수정 내용 (`game/scenes/main.gd`, D-047)

| 항목 | 구현 |
|---|---|
| 눌린 입력 장부 `_held` | `_input`(모든 이벤트, GUI가 소비하기 전)과 `_handle_key_event`(합성 이벤트)에서 press/release를 이름("Escape", "Enter", "R", "mouse1")으로 기록. 재시작은 장부를 건드리지 않고(장치 상태), 창 포커스 손실 시에만 비움 |
| 해제 펜스 `_fence` | `_sync_menu`가 메뉴 열림→PLAYING 전이를 감지한 프레임에 `_held` 사본을 펜스로 삼는다. release마다 그 입력을 펜스에서 지우고, 펜스가 빌 때까지 마우스 press(좌/우)와 1~4/T/C를 거절해 `fenced_inputs`에 기록. 거절한 press는 `_mouse_down`을 세우지 않아 홀드 재시도로 넘어가지 않는다 |
| 닫는 경로별 | Esc(press에 반응) → 뗄 때까지 닫힘. Enter/마우스 클릭 → Button이 release에 `pressed`를 내므로 닫히는 시점에 눌린 것이 없어 펜스가 비어 새 press부터 즉시. RESULT의 R → 새 런에서 R을 뗄 때까지 닫힘 |
| 홀드 재시도 | 이전 런 홀드 폐기(R-03)는 펜스와 무관하게 유지, 재시도 자체는 펜스가 빈 동안만 |
| 종료 우선순위 | `_physics_process`가 의도 큐 적용 **전에** `_check_run_end()`를 호출: 루프 밖에서 진행되어 이미 끝난 런은 RESULT가 먼저 서고 대기 pause는 stale |
| 캡처 | `key` 스텝은 탭(press+release). 새 `fence_probe` 스텝(붕괴 전 1회, WON 런 1회)이 Esc 일시정지 → Esc 누른 채 재개 → LMB press(거절) → Esc release → LMB press(배치)를 실제 이벤트로 기록. `ui_state_log`에 `fence`/`fenced_inputs` 추가 |
| 테스트 러너 | `run_tests.gd`가 첫 프레임에서 스위트를 실행(`_initialize` 안에서는 root Window가 `push_input`을 노드에 전달하지 않음) |

#### 재시험 (리뷰 요청 항목별)

| 요청 | 시험 | 결과 |
|---|---|---|
| Esc held + LMB | AC-05 R-01 (a): Esc 재개 후 release 없이 LMB press | accepted Δ0 · rejected 0 · 회수권 1 · `fenced_inputs` 1건("mouse1") · `_mouse_down` false · 30프레임 후에도 Δ0 |
| 차단 중 누른 LMB를 계속 hold | (a) 이어서 Esc release 후 30프레임, LMB release | Δ0 유지(재시도 없음), release도 Δ0 |
| release 후 새 press | (a)/(b)/(d)/(e) | 정확히 Δ1, H1이 B에 배치 |
| Enter held + 버튼 | (b): `_input`에 Enter press 기록 후 계속하기 `pressed` 신호 | 펜스 ["Enter"], LMB Δ0; Enter release → 펜스 빔 → 새 press Δ1 |
| 닫기 클릭의 press/release | (c): 버튼 위 press(장부 "mouse1")·release 후 신호 | 펜스 빔, 닫는 클릭 Δ0, 다음 새 press Δ1 |
| 재시작 뒤 지연 입력 | (d): RESULT에서 R press(미해제) → 새 런 → 붕괴 후 LMB | 펜스 ["R"] 유지, LMB Δ0; R release → 새 press Δ1 |
| Viewport 입력 경로 | (e): `Window.push_input`으로 Esc press/release·LMB press/release | PAUSED → PLAYING, Esc 보유 중 LMB Δ0·미배치, release 후 새 press Δ1·배치. 리뷰 스크립트 `review_input.gd`의 `viewport_input` 케이스와 동일 순서 |
| 종료 우선순위 경계 | "run already LOST before pending pause": pause 큐 후 `battle.step`으로 LOST, 1프레임 | UI RESULT(리뷰 관측의 PAUSED 아님), pause stale 1건, 결과 모델 LOST |
| 기존 AC-05 | Esc 재개 후 press → Δ0, Esc release 후 새 press → Δ1로 갱신(이전 시험은 Esc를 떼지 않은 채 새 press를 넣고 있었음) | PASS |
| 전체 회귀 | `verify.ps1 -Wp004` | **1,106 passed / 0 failed (56.2 s; 기존 780 + WP-004 스위트 14케이스, 보완 회차에서 +53 체크)**, 종료 0 |

#### 증거

- 테스트 리포트: `results/evidence/wp-004/tests/test_report.txt`(보완 회차로 갱신, 이전 리포트는 `gpt-review/2026-09-19/test_report.txt`에 리뷰어 재실행본이 남아 있음).
- 캡처(재생성, 11장 × 2 해상도 + 로그): `wp004_ui*_log.json`의 `fence_probe` 2건 — 붕괴 전: 상태 PAUSED→PLAYING, 펜스 ["Escape"], Esc 보유 중 LMB Δ0, release 후 Δ0(회수권 없음 → 배치 거절); WON 런: Esc 보유 중 Δ0·미배치, release 후 Δ1·`recovery_placed` true. 두 해상도 동일.
- 새 release(`a24e3fe`) 성능: collapse_move **200.4 FPS / p95 14.66 ms**, collapse_combat **229.2 FPS / p95 13.36 ms**, 전 프레임 alive ≥1000, 6 이벤트, 배치 ok, exe SHA-256 `a1aebd868e19cfb410d8d261daa7dd08ab4a8600418554fef5633ac0960a25ae` (`results/evidence/wp-004/perf/`, 이전 회차 파일을 덮어씀; manifest `implementation_sha` = `a24e3fe`, 외부 메모리 샘플러 기록의 exe 해시 일치). 1차 제출(221.1 / 250.2 FPS)보다 낮지만 D-009 예산(평균 ≥60, p95 ≤25 ms) 안이다. 이번 변경은 이벤트당 장부 갱신뿐이라 측정 구간(입력 없음)에는 영향이 없고, 같은 기기에서의 회차 간 편차로 본다. 이 판단의 근거는 두 회차 모두 alive 1000 고정·6 이벤트 동일이라는 점이며 별도 A/B 측정은 하지 않았다(NOT RUN).
- 리뷰어 재현 스크립트 `gpt-review/2026-09-19/review_input.gd`는 헤드리스에서 그대로 실행 가능하며, 수정 후 기대값(`release_fence` Δ0, `viewport_input` Δ0, `terminal_boundary` RESULT)을 만족한다: `release_fence Δ0(미배치, PLAYING) · viewport_input Δ0(미배치) · terminal_boundary RESULT — 출력은 수정본에서 다시 얻었고 리뷰어의 input_review.json 파일은 그대로 둠`.

#### 알려진 한계

- 실제 창 포커스 손실 시 장부를 비우는 경로는 헤드리스로 시험하지 못했다(NOT RUN; 코드는 `NOTIFICATION_APPLICATION_FOCUS_OUT`/`WM_WINDOW_FOCUS_OUT`).
- Enter로 닫는 경로의 "Enter를 누른 채"는 Button이 release에 신호를 내는 Godot 기본 동작상 닫힘 자체가 release 뒤에 일어난다. 시험 (b)는 그 가정이 깨져도(press 모드 버튼) 펜스가 지키는지를 `_input` 장부로 확인한 것이다.

### 2026-09-20 — GPT 재리뷰 / 보완 회차 1 / PR #6

- 최종 판정: **PASS**. 이전 R-01 해소, AC-01~08 모두 PASS. 본 판정은 2026-09-19 REVISE를 대체하며 이전 기록은 보존한다.
- 검토 diff: `0f1f166..128c467`. 검증 구현: `a24e3fefa17687d3cacd4eb500b393682bcc75c7`, 제출 문서·증거: `128c467`. 구현 커밋 이후 `game/` 및 `project.godot` 차이 없음.
- 독립 전체 회귀: Godot 4.7.stable.official.5b4e0cb0f, **1,106 PASS / 0 FAIL, 63.0초, 종료 코드 0**.
- 독립 증거: `results/evidence/wp-004/gpt-review/2026-09-20/` — `test_report.txt`, 이전 재현을 경로만 바꾼 `review_input.gd`/`input_review.json`, 실제 버튼 입력 `gui_review.gd`/`gui_review.json`, 성능 재계산 `audit_perf.ps1`/`perf_audit.json`.

| AC | GPT 판정 | 검증 근거 |
|---|---|---|
| AC-01 | PASS | F1/F2/F4·시작·결과·재시작/복귀 회귀 통과. Enter 및 마우스로 계속하기 버튼을 Viewport 입력 경로에서 직접 조작하여 PLAYING 전이도 독립 확인 |
| AC-02 | PASS | PAUSED/SETTINGS/CONFIRM 각각 120프레임 전투 상태·배치 불변 및 재개 후 시간 몰아처리 없음 재실행 통과 |
| AC-03 | PASS | 진행 중 확인/취소·원래 UI 복귀·RESULT 즉시 재시작과 중복 요청 폐기 재실행 통과 |
| AC-04 | PASS | 진행 중/WON/LOST 후 새 초기 상태·run_id·이전 홀드 폐기 통과. 새 런에서도 R을 떼기 전 지연 LMB 차단 시험 통과 |
| AC-05 | **PASS** | 이전 직접 핸들러/Viewport 재현 모두 accepted_delta=0·미배치. 차단 중 LMB hold를 해제 이후까지 유지해도 배치 0, 이후 새 press에만 1회. Enter/마우스 실제 버튼의 닫는 입력 배치 0, 다음 새 press 배치 1회. 이미 LOST인 런의 pending pause도 RESULT 우선 |
| AC-06 | PASS | 실제 장부의 승패·시간·웨이브·처치/도달·붕괴·회수·핵심 HP 및 RESULT 동결 회귀 통과. 새 승리 캡처의 01:45·1073처치·외곽36/핵심32도 로그와 일치 |
| AC-07 | PASS | 설정 저장/복원·손상/누락/실패 회귀 통과. 메뉴 레이아웃 코드는 변경 없음, 기존 두 해상도 검토 유지 및 새 720p 승리/1080p 확인창 대표 캡처 재확인 |
| AC-08 | PASS | 기존 회귀 포함 1,106건 통과. legacy8존/WP-00310존·자동 모드 우회 유지. 새 release 원시 배열·구간·6 이벤트·구현 SHA/실행파일 해시 대조 통과 |

#### R-01 해소와 실제 입력 경로 확인

`_input`에서 GUI 소비 전 눌림/해제를 기록하고 메뉴→PLAYING 전이 때 해제를 기다릴 입력 집합을 만든다. 이 집합이 비기 전의 배치 입력은 전투 명령과 held 재시도 모두로 전달하지 않는다. 기존 재현 스크립트는 원래의 잘못된 동작을 더 이상 발생시키지 않는다. 추가 `gui_review.gd`는 Button 신호를 수동 발생시키지 않고 실제 Viewport 키/마우스 이벤트를 사용한다. Enter와 마우스 모두 press 시 PAUSED, release 시 PLAYING, 닫는 입력의 배치 0, 이후 새 전장 press의 배치 1을 확인했다. 마우스 이벤트는 버튼의 논리 좌표와 일치하도록 `push_input(..., true)`를 사용한다.

두 해상도 캡처 로그의 `fence_probe` 각 2건도 대조했다. Esc를 누른 동안 accepted_delta=0이며, 붕괴 후에는 release 뒤 새 press에서만 accepted_delta=1·recovery_placed=true다. 붕괴 전에는 release 뒤에도 회수권이 없으므로 배치가 거절된다. 기존 배치 규칙을 우회하지 않는다.

D-047의 입력 장부/해제 대기와 종료 우선순위 보완을 수용한다. 이번 변경은 기획의 D-039~042를 충족하며 전투 수치·회수권·재시작 초기 조건 변경이 아니다.

#### 새 release 증거의 독립 재계산

| 시나리오 | 프레임 수 | 평균 FPS | p95 ms | alive 최솟값 | 결과 |
|---|---:|---:|---:|---:|---|
| collapse_move | 12,025 | 200.39 | 14.660 | 1,000 | PASS |
| collapse_combat | 13,756 | 229.23 | 13.362 | 1,000 | PASS |

`frame_us_raw`/`alive_raw`, 구간 인덱스 연속성과 전체 매핑, 구간 FPS/p95·후보 평가 증가, 10존/18시설, semantic event6건, trigger→collapse0틱, 배치ok, path_version4→5를 확인했다. 양쪽 manifest의 구현 SHA는 `a24e3fe`, 실행파일 SHA-256은 `a1aebd868e19cfb410d8d261daa7dd08ab4a8600418554fef5633ac0960a25ae`이며 외부 메모리 샘플러와 일치한다. combat의 H1 재배치 이후 발사42회도 유지된다.

이전 회차보다 평균 FPS가 낮지만 D-009/027 예산은 충족한다. 동일 부하·이벤트만으로 원인을 기기 편차라고 확정할 수는 없으므로 원인 판단은 유보한다. 원인 규명을 위한 통제 A/B 시험은 NOT RUN이며 이번 합격 기준에 추가하지 않는다.

#### 검증 범위와 후속 처리

전체 회귀·이전 재현·실제 Viewport 버튼 경로·원시 성능 재계산은 리뷰어가 직접 실행했다. release export와 10+60초 성능 측정, OS 전체화면 전환, 실제 창 포커스 손실/복귀는 이번 재리뷰에서 별도 실행하지 않았다(NOT RUN). 성능과 화면은 제출된 새 release JSON/PNG 및 이전 검토를 근거로 하며, 창 설정은 기존 구현자 수동 확인과 재실행한 저장/복구 테스트 범위를 유지한다.

필수 보완 요청은 없다. GPT PASS에 따라 WP-004 완료 정리와 병합 준비가 가능하다. 이 리뷰는 결과 문서·검증 증거만 반영하며 PR 병합은 수행하지 않는다.
