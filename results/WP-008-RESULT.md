# WP-008 Result

- 작성일: 2026-09-20
- WP / 상태: WP-008 준비 배치·전투 중 건설·물자 / **REVIEW** (GPT 1차 REVISE 2026-09-20 → 보완 회차 1 `8da6755` → 사용자 요청 추가 `28be613`, 재리뷰 PENDING; 하단 참조)
- 기준 커밋: `f39911a` ("docs: plan build economy and siege progression with WP-008 handoff", `wp/005-art-sample`, D-054 READY). 착수 SHA = 기준 커밋.
- 검증한 구현 커밋: **`ebe263a`** (1차 제출) → **`8da6755`** (보완 회차 1, R-01~03). 결과·증거 커밋: 이 문서의 커밋(별도 문서 커밋으로 자기참조 회피).
- 브랜치: `wp/008-build-economy` (base `wp/005-art-sample`, stacked Draft PR: https://github.com/darkrunar/hanyang-defense/pull/13). main 병합은 사용자 지시로만.
- 실행 환경 / 엔진·버전: Godot 4.7.stable.official.5b4e0cb0f (GDScript, 2D, gl_compatibility) · Windows 11 Home 10.0.26200 · AMD Ryzen 5 7600 · NVIDIA GeForce RTX 4070 SUPER · 63.2 GB · 1920×1080 창(캡처는 1280×720도) · vsync off · 보이는 창(D-009 절차)

이 문서는 `results/RESULT_TEMPLATE.md` 양식을 따른다. 수치는 `results/evidence/wp-008/` 원시 파일에서 가져왔고, 승인된 WP-001~005 증거는 건드리지 않았다(`verify.ps1 -Wp008`). 계약은 [backlog/WP-008.md](../backlog/WP-008.md)(D-054)이며 구현자가 정한 자료구조·정산 순서·입력 경계는 [D-055](../docs/DECISIONS.md)에 기록했다. 기존 WP-003/004 규칙(HP 360/60·10존·1,140체·회수 1회·승패 우선순위·메뉴·해제 펜스)과 WP-005 렌더링은 바꾸지 않았고, 기본 실행(`--play-mode` 없음)은 WP-003 런 그대로다.

## 구현 결과

| 파일 | 목적 |
|---|---|
| `game/core/economy.gd` (신규) | 물자 장부: 정수 잔액, 불변식 `supply == 시작 + 처치 + 웨이브 + 주입 − 소비`, 처치 보상(개체당 1회)·웨이브 보상(인덱스당 1회)·차감(배치 성공 뒤)·거절 집계·벤치마크 주입 표시·이벤트 로그 |
| `game/core/battle.gd` | `play_mode`/`preparing`/`begin_defense()`(1회, 거절 집계), `step()` 준비 중 무동작, 정산 `_settle_economy()`(사격→도달→붕괴 뒤, 승패 앞), `preview_build()`/`buy_structure()`(런 종료→모드→상한→잔액→셀 규칙, 원자적 배치·설정·차감), `structure_total()`, fixture `build`, `state_hash`/`full_state`/`snapshot`에 장부·준비 상태 |
| `game/core/wave_director.gd` | `wave_cleared_tick`, `mark_cleared()`(예산 소진 + 생존 0을 처음 본 틱; 상태 전이는 기존 그대로 다음 틱) |
| `game/core/bongsu_network.gd` | 성능(측정 근거): 적 슬롯별 존 소속 비트마스크를 탐지 패스당 1회 계산해 `known_zone_counts`가 화차마다 거리 루프를 돌지 않음. 결과 동일(회귀·F3·동일성 검사), 틱 16.05 → 5.37 ms(24시설·1,000체·move). 첫 release 측정 p95 24.50/25.48 ms(경계·FAIL 1회)는 아래 성능 절에 기록 |
| `game/core/play_flow.gd` | `PREPARING` 상태, `build_mode`, `begin_defense()`(PREPARING에서만), `field_active()`, 일시정지/설정/확인창의 복귀 대상(`pause_return`), RESULT/확인 재시작이 build면 PREPARING으로 |
| `game/core/placement.gd` | 거절 사유 `BUILD_DISABLED`/`CAP_REACHED`/`INSUFFICIENT_SUPPLY`, 사용자용 사유 문구 `reject_ko()` |
| `game/core/config.gd` | `play_mode`, `start_supply`, `kill_reward`, `wave_reward`, `cost_*`, `structure_cap`, `benchmark_supply`(전부 `--set` 가능), `Config.for_wp008()` |
| `game/core/result_model.gd` | 결과 모델에 `play_mode`·`economy`, 결과 화면 행 `economy_lines()`(build에서만) |
| `game/maps/hanyang_test_map.gd` | `FIXTURE_BUILD`(화차·중영/궁성, 봉수 B8, 혼천의 S3). fixture C 불변 |
| `game/scenes/main.gd` | `--play-mode=build`(`--set`처럼 고정), 건설 바(실제 Button: 1~4 종류·5 회수·방어 시작), 키 1~5/Space, LMB 새 누름 1회당 최대 1회 구매(홀드 재시도 없음; 회수 배치만 재시도), 붕괴 시 회수 선택 자동 전환, HUD 장부·준비 안내, 캡처 `wp008_build[_720]`(스텝 `hud_button`/`lmb_at`/`econ_log`, `preview_at` 건설 고스트), 성능 `build_full_*`/`build_grow_*`(D-027 기계 공유 + 구매 명령 장부), manifest에 `play_mode`/`economy` |
| `game/scenes/overlay_layer.gd` | 건설 고스트(`preview_build`와 같은 규칙: 비용·잔액·부족·상한·사유) |
| `game/scenes/menu_layer.gd` | PREPARING에서 메뉴 숨김, 준비 중 일시정지 안내문, 결과 화면 경제 행 |
| `game/tools/wp008_compare.gd` (신규) | AC-09: 같은 시드의 무건설 vs 전략 4종(준비 전용·광장 화차·봉수망 우선·병목), 초 단위 잔액·구매·피해·승패·명령 수 JSON |
| `tests/test_build_economy.gd` (신규), `tests/run_tests.gd` | AC-01~06 코어·scene(실제 버튼·키·마우스 이벤트) 18케이스 |
| `scripts/verify.ps1`(`-Wp008`), `scripts/verify.sh`, `scripts/perf_with_memory.ps1` | 4f 캡처 2종(상태·장부·클릭 검사), 4g AC-09 비교, 6e 성능 4종(D-027 계약 + 장부·상한·구매 검사; `Assert-CollapsePerf`에 시작 시설 수 인자) |
| `README.md`, `docs/GAME_GUIDE.md`(8.6·9.1·11·12), `docs/DECISIONS.md`(D-055), `docs/ROADMAP.md`, `backlog/WP-008.md` | 실행 방법·규칙·조작·설정·결정 기록·상태 |

## 실행·재현 절차

필요 도구: Godot 4.7.stable(`godot` PATH), Windows export template(빌드·성능), PowerShell(성능 샘플러). 추가 패키지 없음.

```bash
git clone https://github.com/darkrunar/hanyang-defense.git && cd hanyang-defense && git checkout wp/008-build-economy
```

| 단계 | 명령 | 산출물 |
|---|---|---|
| 자동 검증(기존 회귀 1,322 + WP-008) | `godot --headless --path . --script res://tests/run_tests.gd -- --report=<abs>/results/evidence/wp-008/tests/test_report.txt` | **1,671 passed / 0 failed (87.1 s; 기존 1,322 + WP-008 스위트 18케이스 349체크)**, 종료 0 |
| 건설 모드 캡처 | `godot --path . --rendering-driver opengl3 -- --capture=wp008_build --out-dir=<abs>/results/evidence/wp-008/captures --settings=<abs>/…/settings_capture.cfg` (`wp008_build_720` 동일) | PNG 17장 × 2 해상도 + `wp008_build*_log.json`(상태 전이·버튼·클릭·장부·결과) |
| AC-09 비교 | `godot --headless --path . --script res://game/tools/wp008_compare.gd -- --out=<abs>/results/evidence/wp-008/compare/ac09_compare.json` | 전략별 요약·타임라인·명령 로그 |
| 릴리스 빌드 | `godot --headless --path . --export-release "Windows Desktop Release" build_out/windows/hanyang_defense_wp001.exe` | exe |
| 성능 | `.\scripts\perf_with_memory.ps1 -Scenario build_full_move\|build_full_combat\|build_grow_move\|build_grow_combat -Warmup 10 -Measure 60 -Out results\evidence\wp-008\perf\perf_<sc>_1000_release.json` | 원시 배열·구간·이벤트·구매 명령·장부·manifest·exe 해시 |
| 일괄 | `.\scripts\verify.ps1 -Wp008` | 위 전부 + 계약 검사, 종료 0 |
| 플레이 | `godot --path . --rendering-driver opengl3 -- --play-mode=build` | 시작 화면 → 준비 단계. 조작은 README / GAME_GUIDE 8.6·9.1 |

설정: 시드 20260913, 60 Hz 고정, WP-003 계약값 + WP-008 초기값(물자 240, 처치 1, 웨이브 80, 비용 40/100/60/80, 상한 24) 그대로. 캡처는 `--settings`로 임시 파일을 주입해 실제 사용자 설정을 건드리지 않고, 50 s 강제 붕괴(검증 전용 훅, 로그 `forced_hp_writes`)로 런을 짧게 만든다. 강제 훅은 메뉴·건설 바에 노출되지 않는다. 성능은 `benchmark_supply=3000` 주입(장부·manifest `benchmark_injected=true`)으로 시설을 24개까지 사며, 정상 경제 증거로 쓰지 않는다.

## Acceptance Criteria

| AC | PASS / FAIL / NOT RUN | 기대 결과 | 실제 결과 | 증거 파일·로그·화면 |
|---|---|---|---|---|
| AC-01 | **PASS** | 새 모드 진입 → 준비 120틱 생성/시간 불변 → 1회 방어 시작. 초기 시설 좌표/회수 ID/물자 정확. 기존 기본 실행/fixture 보존 | `--play-mode=build`: TITLE → 게임 시작 → PREPARING. 코어 120틱·scene 120프레임 모두 steps 0·sim_time 0·생성 0·full_state 동일. 초기 4시설 id 1~4 = 화차·중영(46,29)·화차·궁성(46,17)·봉수 B8(44,33)·혼천의 S3(44,39), 회수 대상 id 1, 물자 240, 상한 24. `begin_defense` 1회 수락(이벤트 1건), 두 번째는 흐름이 거절하고 코어는 보지 못함(`begin_defense_calls_ignored` 0), 웨이브 W1 tick 0 시작. 재시작 → 다시 PREPARING·240·4시설. 기본 실행은 classic(fixture C 18, 장부 off, 건설 바 없음, 1~4 거절), `collapse_*` 시나리오도 classic 유지 | 테스트 "AC-01", "scene AC-01", "Config / fixture", "scene: the classic launch", "scene entry paths"; 캡처 `01_preparing`, 로그 `start_goes_to_preparing`/`begin_defense_playing`/`second_begin_defense_refused` |
| AC-02 | **PASS** | 시작240 + 확정 처치 + 완료 웨이브×80 − 구매 합계 = 잔액. 동시 처치·중복·도달 무보상·중간/최종 웨이브·패배/재시작 경계 | 무건설 + 붕괴 즉시 회수 런(WON 102.8 s): 매 초 불변식·`kills_rewarded == killed_total` 유지, 도달 361건 무보상, 웨이브 [0,1,2] 각 1회(해소 틱 = 지급 틱, 마지막 웨이브는 런을 끝낸 step 안에서), 최종 잔액 = 240 + 처치 + 240. 12체 동시 처치 1볼리 → +12 정확. 예산 소진만으로는 미지급(생존 0 될 때 1회), 중복 clear/지급 거절. LOST 뒤 120틱 지급·이벤트 0, 구매 RUN_ENDED. 재시작 → 240·처치 0·웨이브 0 | 테스트 "AC-02 ledger", "AC-02 boundaries", "Economy unit"; 캡처 로그 `econ_log`(모든 지점 `balance_ok` true), 결과 화면 `16_result` 물자 식 |
| AC-03 | **PASS** | 네 시설 성공 구매·모든 거절 조건·상한24·잔액 정확. 실패 시 HP/점유/경로/시설/물자 불변. 장승 경로 변경, 비차단 시설·봉수 연결 | 장승 −40(경로 버전 +1, 3경로 도달 유지) · 봉수 −60(경로 불변, 망 위상 +) · 혼천의 −80 · 화차 −100(부착·사거리 설정, 라벨 `화차+4`). 거절 11종(잔액 부족·겹침·벽·지도 밖·구역 걸침·미지 종류·전체 경로 차단·적 점유·상한·붕괴 외곽·런 종료) 각각 `state_hash`·물자·소비·시설 수·경로/망 버전·HP 불변, 사유별 집계. 상한: 24에서 25번째 CAP_REACHED, 마지막 슬롯 중복 입력 2번째 거절, 회수 대기 포함(붕괴 뒤 24 유지·회수 뒤 24 유지·회수 비용 0). 원거리 화차 미부착 → 봉수 구매 뒤 기존 망 갱신 경로로 부착 | 테스트 "AC-03 purchases", "AC-03 cap"; 캡처 `02`(비용 미리보기) `03`(준비 구매 3건 → 40) `04`(부족) `05`(벽) `06`(겹침) `13`(붕괴 후 외곽 거절) |
| AC-04 | **PASS** | 유료 클릭 1회 1개, 홀드·UI 클릭·Esc 해제·취소·모드 전환 누수 없음. 무료 회수 홀드 재시도 유지 | 실제 마우스 이벤트: press 1회 → 구매 1(수락 delta 1), 누른 채 30프레임·다른 셀 이동 → 0, 거절(겹침·부족) 뒤 30프레임 자동 재구매 0. 건설 바 버튼 press → 선택만(수락 0, 물자 불변). 메뉴 중 클릭 → 0. Esc 누른 채 press → 펜스 거절(`fenced_inputs` mouse1·1), 뗀 뒤 새 press → 구매. 재시작·선택 변경 → `_mouse_down` 해제. 회수 선택 press → 홀드 재시도(5프레임 ≥3회 거절) 유지, 5↔1~4 전환. 캡처 로그의 모든 `lmb_at`은 `accepted_delta ≤ 1` | 테스트 "scene AC-04", "scene: HUD buttons", "scene: Esc pauses PREPARING", "scene: recovery placement"; 캡처 로그 `lmb_at`/`hud_button` |
| AC-05 | **PASS** | 실제 도달 붕괴, 외곽 신규/초기 시설 비활성, 초기 중영만 무료 회수, 구매 시설 비용/ID/상한 일관, 내곽 증설 후 계속 전투 | 실제 도달 피해로 붕괴(강제 HP는 검증 훅, 도달은 실제): 구매한 외곽 화차·초기 외곽 시설 비활성(점유 유지), 분리는 id 1뿐, 총수 불변. 무료 회수 B(같은 id, 물자·구매 수 불변) → 외곽 구매 DISTRICT_LOST(미리보기 일치) → 내곽 (50,8) 구매 ok·활성 → 내곽 구매 화차 사격. 캡처: 붕괴 시 회수 선택 자동 전환(`10`), B 미리보기·배치(`11`/`12`, spent 불변), 외곽 거절(`13`), 내곽 미리보기·구매(`14`/`15`) | 테스트 "AC-05"; 캡처 `10`~`15`, 로그 `after_collapse`/`after_recovery`/`after_inner_purchase` |
| AC-06 | **PASS** | 승리/패배/재시작 시나리오·기존 전체 회귀 통과. 새 모드도 동일 seed/명령의 greybox/sample 상태 일치(장부 포함) | 전체 1,671 passed / 0 failed (87.1 s; 기존 1,322 + WP-008 스위트 18케이스 349체크) 종료 0(기존 1,322 전부 포함). 코어: 같은 명령 2회 → `full_state_json` 동일(장부 포함). scene: greybox/sample 같은 스크립트(준비 구매·방어 시작·240프레임·전투 구매·120프레임) → 동일. 승리(캡처 결과 WON)·패배(테스트 LOST → RESULT 경제 행)·재시작(R → PREPARING·장부 초기화) | 테스트 "AC-06", "scene AC-06", "scene: R -> confirm"; 캡처 `16_result`/`17_restart_preparing` |
| AC-07 | **PASS** | 1080p/720p release 캡처: 준비/건설 선택/부족/무효 배치/전투 중 구매/붕괴/무료 회수/내곽 구매/결과. 비용과 무료 배치 혼동 없음, 문자 겹침 없음, 구현 SHA·exe 해시·상태 JSON | 두 해상도 각 17장(아래 "실제 화면 확인"). 비용 고스트("화차 건설 100 → 잔액 140" / "물자 부족: 화차 100 필요 · 잔액 40")와 회수 고스트("배치 가능", 바 "5 회수 화차 1/1")가 문구·색으로 구분됨. 720p에서 건설 바·HUD·고스트 문자 겹침 없음(Claude 육안; 가독성 판정은 GPT). 상태 JSON은 캡처 로그(`econ_log`·`ui_state`·`lmb_at`), exe 해시는 성능 manifest. 캡처는 에디터 실행(release 캡처 모드는 기존 WP와 같은 방식) | `captures/wp008_build_*.png`, `wp008_build_720_*.png`, `*_log.json` |
| AC-08 | **PASS** | 24시설(화차 비중·연결망 구성) 1,000체 유지 warmup10+measure60, 측정 중 장승 경로 변경·구매·붕괴·회수 장부, 평균 ≥60 FPS/p95 ≤25 ms/모든 alive ≥1000, 원시 배열·메모리·장비·창 조건. 기존 fixture 보존 | 4시나리오 모두 예산 충족(아래 표). full: 시작 24(화차 12·봉수 5·혼천의 5·장승 2), 창 안 구매 0·상한 거절 1; grow: 시작 22(화차 6→7·봉수 8·혼천의 6·장승 2→3), 창 안 장승·화차 구매 2건(경로 재계산 1회)·상한 거절 1, 종료 총수 24. 트리거→붕괴·회수 B 배치 ok, 6 이벤트, 구간 합 = 전체 프레임, 장부 불변식·주입 표시(injected 3000) 확인. 기존 collapse_*(fixture C) 증거는 그대로 | `perf/perf_build_*_1000_release.json` (+`.memory.json`) |
| AC-09 | **PASS** (재미·균형 판정은 GPT) | 같은 seed 무건설 vs 계획 건설 비교(잔액/건설 타임라인/거점 피해/승패/입력 수), 최소 1개 합법 전략 승리, 준비+전투 중 구매+무료 회수 경로 모두 증명 | `wp008_compare.gd`(시드 20260913): 무건설(붕괴 즉시 회수만) 55.6 s 붕괴·핵심 54·WON 102.8 s; 준비 전용(화차·장승·봉수 200) 88.3 s 붕괴·회수 ok·핵심 60·WON; 광장 화차/봉수망 우선/병목(준비 + 전투 중 구매 9건) 89.8~97.0 s 붕괴·핵심 60·WON. 5전략 모두 불변식·식 일치. 준비 구매(전 전략)·전투 중 구매(3전략, 첫 구매 10.4~26.2 s)·무료 회수(no_build 55.6 s, prep_only 88.3 s) 각각 증명. 캡처 런도 준비 3건 + 전투 중 2건 + 회수 + 내곽 1건으로 WON | `compare/ac09_compare.json`; 캡처 로그 |

자동 검증 합계: **1,671 passed / 0 failed (87.1 s; 기존 1,322 + WP-008 스위트 18케이스 349체크)**, 종료 코드 0.

## 성능

- OS / CPU / GPU / RAM / 해상도 / 빌드 설정: 위 실행 환경. exported release, gl_compatibility, 1920×1080, vsync 0, 보이는 창(D-009 절차, PR #12 리뷰 반영). 실행파일 SHA-256 `b557ec69bb234174e26aae32ea45d9556e935abf88ea0c260d6f6e3bc13cac25`(게임 자체 기록 = 외부 Get-FileHash). 렌더링 greybox(WP-005 아트는 별도 트랙; `--art=sample`은 WP-005 증거로).
- 시나리오: D-027 전환 벤치마크(`benchmark_hold_alive` 1,000체·웨이브 off·외곽 HP 1e6 → 측정 20 s 트리거·25 s 회수 B·핵심 무적 집계)를 build 프로필 위에서. `build_full_*` = 시작 24시설(초기 4 + 준비 구매 20: 화차 10·봉수 4·혼천의 4·장승 2 → 화차 12), 창 안 5 s 구매 시도 1건은 상한 거절. `build_grow_*` = 시작 22(초기 4 + 준비 구매 18: 화차 4·봉수 7·혼천의 5·장승 2 → 화차 6·봉수 8·혼천의 6·장승 2), 창 안 5 s 장승(31,17)·10 s 화차(64,17) 구매(→24, 경로 재계산 1회), 12 s 상한 거절(광장 모서리 셀: 첫 시도의 골목 (22,28)은 1,000체 유지 중 창 내내 적 점유로 1,530회 거절돼 구매가 이루어지지 않았고, 붕괴 뒤 광장은 DISTRICT_LOST — 그 실행은 FAIL로 기록하고 셀만 바꿔 재측정). 준비 구매는 `benchmark_supply` 3000 주입(표시)으로 결제.

| 시나리오 | 프레임 / 초 | 생존 min / avg | 평균 FPS | 프레임 ms p50 / **p95** / p99 / max | 구간 [0,20) / [20,25) / [25,60] avg FPS · p95 | 창 안 구매 ok / 상한 거절 | 6 이벤트·배치·pv | 워킹셋 MB | 판정 |
|---|---|---|---|---|---|---|---|---|---|
| build_full_move | 7,530 / 60.00 | 1000 / 1000.0 | **125.5** | 5.11 / **23.82** / 26.61 / 36.38 | 100.5·25.62 / 141.3·22.78 / 137.5·22.93 | 0 / 1 | 6건 · ok · pv 4→5 | 180→127.9 | PASS |
| build_full_combat | 7,722 / 60.01 | 1000 / 1000.0 | **128.7** | 4.84 / **23.73** / 28.18 / 35.10 | 107.4·25.22 / 141.5·23.14 / 139.0·23.00 | 0 / 1 | 6건 · ok · pv 4→5 | 179.7→128.4 | PASS |
| build_grow_move | 8,412 / 60.00 | 1000 / 1000.0 | **140.2** | 4.75 / **20.53** / 24.25 / 39.58 | 116.7·22.05 / 157.1·20.29 / 151.2·20.00 | 2 / 1 | 6건 · ok · pv 4→6 | 178.8→186.5 | PASS |
| build_grow_combat | 9,454 / 60.01 | 1000 / 1000.0 | **157.5** | 4.03 / **19.20** / 21.76 / 29.89 | 131.4·20.67 / 178.2·18.00 / 169.5·18.52 | 2 / 1 | 6건 · ok · pv 4→6 | 182.8→0 | PASS |

- 최적화 전 측정(같은 exe 계열, 기록 보존): 첫 실행 build_full_move 114.3 FPS / p95 24.50 ms(PASS 경계), 두 번째 실행 106.7 FPS / **p95 25.48 ms(FAIL)**, 구간 [0,20) 52.6 FPS·p95 44.88 ms(화차 12 전부 활성) vs [25,60] 133.3 FPS·23.18 ms(붕괴 뒤 외곽 화차 비활성). 헤드리스 프로파일: 틱 16.05 ms 중 `known_zone_counts` 12.40 ms, 탐지 2.31 ms → D-055의 존 마스크 최적화 후 틱 5.37 ms(전투 3.97 ms), 인지 집합 크기 동일(2,382 / 1,698). 아래 표는 최적화 후의 새 release 측정이다. 첫 grow_move 실행은 골목 (22,28) 구매가 창 내내 적 점유로 1,530회 거절돼 계약 미충족(FAIL, `perf/run1_fail/` 보존) → 광장 모서리 셀로 재측정. 두 번째 실행은 10 s 화차 셀 (62,17)이 준비 구매 (62,18)과 겹쳐 STRUCTURE_OVERLAP으로 거절되고 세 번째 구매가 성공해 상한 거절이 없었다(스크립트 오류, FAIL, `perf/run2_fail/` 보존; 148.5 FPS / p95 19.87 ms) → (64,17)로 수정해 재측정.
- 예산(D-009 평균 ≥60 FPS·p95 ≤25 ms·전 프레임 alive ≥1000), D-027(6 이벤트·트리거→붕괴 ≤2틱·배치 ok·pv 기대+1·구간 평가 >0), R-05(구간 완전 매핑·manifest 존 10/시설 24 또는 22·exe 해시), WP-008 추가 검사(장부 불변식·주입 표시·상한 거절 ≥1·grow 구매 정확히 2·full 구매 0·종료 시 총수 24·미처리 명령 0) 모두 통과. 기존 `collapse_*`(fixture C)·WP-005 성능 증거는 그대로다.

## 실제 화면 확인

`--capture=wp008_build`(1920×1080)와 `wp008_build_720`(1280×720)가 같은 스크립트를 실제 건설 바 버튼(`pressed` 신호)·실제 키·마우스 이벤트로 재생한다. 각 PNG와 같은 시각의 로그가 `wp008_build*_log.json`에 있다. 준비 단계는 시간이 흐르지 않으므로 `t=0.0`이고, 전투는 6배속이다.

| 캡처 | 관측 |
|---|---|
| `01_preparing` | 게임 시작 직후 PREPARING: HUD "건설 모드 물자 240 = …", "준비 중: 시간·생성·웨이브 정지" 안내, 우하단 건설 바(1 장승 40 · 2 화차 100 · 3 봉수대 60 · 4 혼천의 80 · 5 회수 화차 —, 방어 시작(Space)), 초기 4시설, 적 0, sim t=0 |
| `02_preview_hwacha_cost` | 화차 선택, (40,20) 고스트 초록 "화차 건설 100 → 잔액 140" |
| `03_bought_in_preparation` | 화차+1 (40,20)·장승+2 (44,36)·봉수대+3 (42,21) 구매 후 물자 40, 시설 7/24, 알림 "건설: 봉수대+3 #7 @(42,21) −60 → 잔액 40" |
| `04_insufficient_supply` | 화차 선택·잔액 40: (52,20) 고스트 빨강 "물자 부족: 화차 100 필요 · 잔액 40", 클릭은 거절(로그 INSUFFICIENT_SUPPLY, 물자 불변) |
| `05_invalid_terrain` / `06_invalid_overlap` | 장승 선택: 벽 (45,15) "벽·지형", 화차·중영 자리 (46,29) "다른 시설과 겹침" |
| `07_paused_in_preparation` | 준비 중 Esc → 일시정지 메뉴("준비 단계가 멈춰 있다…"), Esc → PREPARING 복귀(로그) |
| `08_battle_t20` | 방어 시작 후 20 s: W1 진행, 물자 97(처치 57 − 소비 200 + 240), 건설 바에 방어 시작 버튼 없음 |
| `09_battle_purchase_t45` | 45 s: 골목 (48,36) 장승은 적 점유로 거절(로그 ENEMY_OCCUPIES_CELL, 물자 불변), 광장 (36,24) 화차 구매 ok(W1 보상 80 반영 후) |
| `10_collapse_recovery_selected` | 50 s 강제 붕괴(검증 훅) 직후: 외곽 시설 비활성, 바 "5 회수 화차 1/1" 강조, 알림 "외곽 붕괴 — 회수 화차 배치로 전환" |
| `11_recovery_preview_B` / `12_recovery_placed_free` | B (44,13) 회수 고스트 "배치 가능" → 클릭 배치(같은 id 1, spent 불변, 바 "0/1") |
| `13_outer_refused_after_collapse` | 장승 선택, 외곽 (56,24) 고스트 "붕괴한 외곽에는 설치 불가" |
| `14_inner_preview` / `15_inner_purchase` | 내곽 (50,8) 고스트 "장승 건설 40 → 잔액 …" → 구매 ok, 물자 −40, 시설 +1 |
| `16_result` | 승리 결과 화면: 기존 9행 + "물자 시작 240 + 처치 N + 웨이브 240 − 소비 M = 잔액 K", "건설 장승 2 · 화차 2 · 봉수대 1 (총 5)" |
| `17_restart_preparing` | R → 새 런 PREPARING, 물자 240, 초기 4시설, 장부 0 |
| `wp008_build_720_*` | 같은 17장(1280×720): 건설 바·고스트 문자·HUD 겹침 없음(Claude 육안) |

## 미해결 문제와 설계 변경 제안

1. **밸런스(GPT 판단, AC-09 비고)**: 현재 초기값에서는 무건설이라도 붕괴 뒤 회수만 하면 승리한다(핵심 54/60). 광화문 병목 + 궁성 화차가 핵심을 지키는 WP-003 성질이 그대로다. 건설의 효과는 "붕괴 시점 55.6 → 88~97 s, 핵심 무손상"으로 나타난다. 무건설 패배를 필수로 만들지 않는다는 계약대로 기준을 바꾸지 않았다. 제안 P-020: 외곽 붕괴 전 압박을 높이려면 `outer_hp` 또는 W2/W3 편성(D-025)을 조정하되, 조정값은 GPT가 결정한다(초기값 결과는 `compare/ac09_compare.json`).
2. **잔여 물자**: 세 전투 중 구매 전략도 종료 시 418~439가 남는다(W3 처치 보상이 크다). 구매 슬롯·비용을 올리거나 웨이브 보상을 낮출지는 GPT 판단(제안에 포함).
3. **포화 골목 구매 거절**: 전투 중 골목에 장승을 사면 적 점유로 자주 거절된다(P-007과 같은 현상; 유료 건설은 홀드 재시도가 없어 클릭을 반복해야 함). 캡처 `09`가 그 예다. 계약대로 자동 재구매는 없다.
4. **캡처의 강제 붕괴**: 캡처 런은 50 s 강제 HP(검증 훅)로 붕괴를 만든다(로그 `forced_hp_writes`). 자연 붕괴는 AC-09 비교(55.6~97 s)와 테스트 F-경로가 증명한다.
5. **HUD 밀도**: 준비 안내·장부 줄이 좌상단 HUD를 두 줄 늘린다. V-01(D-053, WP-005 후속)의 기본 표시 정리 대상에 포함시키는 편이 맞다.

## 다음 WP 영향

- WP-009/010: `Battle.buy_structure()`/`preview_build()`가 셀 규칙 앞에 전역 조건을 두는 구조라 성밖 건설 허용 범위·성문 관련 거절을 `validate()` 뒤에 붙일 수 있다. 장부(`economy.gd`)는 보상 종류를 이벤트로 구분하므로 성문 파괴 무보상 규칙은 "이벤트를 만들지 않는" 것으로 지켜진다.
- `PlayFlow.PREPARING`·`pause_return`은 build 모드에서만 쓰이지만 기존 상태 이름·전이 로그 형식은 그대로다(WP-004 테스트 전부 통과).
- 성능 시나리오 `build_*`는 `collapse_*`의 구간·이벤트 기계를 공유한다. 시설 수 검사는 `Assert-CollapsePerf`의 인자로 넘긴다.
- `wave_cleared_tick`는 WaveDirector 스냅샷에 추가됐고(전이 시점 불변) F1/F2 타임라인 수치는 바뀌지 않았다.

## GPT Review

- 검토일 / 검토한 구현 커밋:
- 최종 판정: PENDING
- 기준별 검토 결과:
- 범위 준수 / 기획 일치 / 증거 충분성:
- 보완 요청 또는 다음 WP 준비 사항:


### GPT Review — 2026-09-20 / PR #13 1차

- 검토 범위: `f39911a` → 구현 `ebe263a`, 제출 HEAD `2e1f40137cdafa28ba57e9e0db556ddcfc66c39b`.
- **최종 판정: REVISE.** 기능 회귀는 통과했으나 release 화면과 검증 빌드의 구현 추적 증거가 부족하며 물자 이벤트 순번 오류 보완 필요.
- 이번 수행: 변경 코드/명세/저장된 두 해상도 화면 검토, 전체 테스트 독립 재실행 **1,671 PASS / 0 FAIL (82.1초)**, 네 성능 파일 원시 배열 재계산, 경제 장부 순번 재현. 성능 벤치마크 자체와 release 화면 캡처는 이번 리뷰에서 재실행하지 않음. 격리된 사용자 설정 폴더로 회귀 실행.

#### 보완 요청

1. **R-01 / P2 — 성능 증거를 검토 커밋에 연결.** 네 최종 성능 JSON의 `manifest.implementation_sha`는 모두 `f39911a7ceec94995cb0640f3c79908cc93c2c10-dirty`다. 결과 문서의 검증 구현 `ebe263a`와 연결되는 확정 소스 트리 증거가 없어 같은 exe 해시라는 이유만으로 해당 커밋을 검증했다고 승인할 수 없다. 깨끗한 구현 커밋에서 export 후 네 조건을 다시 실행하고 게임/외부 샘플러의 exe 해시와 구현 SHA를 대조한다. 기존 원시값은 보존하고 JSON의 SHA만 수동 교체하지 않는다.
2. **R-02 / P2 — AC-07의 release 화면 제출.** `scripts/verify.ps1:185-186`은 export 이전에 `godot --path .`로 캡처하며 결과 문서도 에디터 실행이라고 명시한다. 이는 WP-008의 두 해상도 release 화면 요구를 충족하지 않는다. R-01의 동일 release에서 준비→구매/거절→붕괴→무료 회수→내곽 구매→결과→재시작 17장씩과 상태 JSON을 제출하고 실행파일 해시를 연결한다. 실제 사용자 모드와 같은 sample 아트도 확인해 건설 UI와 겹침을 검수한다. 이전 WP-005 캡처로 새 건설 UI의 배포본 검증을 대체하지 않는다.
3. **R-03 / P2 — 구매 이벤트가 전역 seq를 덮어씀.** `economy.gd:71-77`은 `_seq`를 할당한 뒤 data를 복사하며, `charge()`의 구매 순번 `rec.seq`가 전역 이벤트 번호를 덮어쓴다. 재현: 처치 보상→웨이브 보상→첫 구매의 이벤트 seq가 **1,2,1**. 잔액은 정확하지만 seq 기반 정렬/중복 제거에서 구매가 보상과 충돌한다. 구매 순번은 `purchase_seq` 등으로 분리하고 이벤트 seq는 단조 증가·중복 없음, 재시작 뒤 새 런 장부 초기화 회귀를 추가한다.

#### AC 재판정

| AC | 판정 | 근거 |
|---|---|---|
| AC-01 | PASS | 초기 4시설·물자240·PREPARING 120틱 불변·방어 시작·기존 실행 보존 테스트 재통과 |
| AC-02 | PASS (정산 범위) | 처치/웨이브 1회 정산·거절 무차감·재시작 불변식 재통과. 별도 R-03 이벤트 식별 결함은 미해소 |
| AC-03 | PASS | 네 시설·거절·상한24·점유/경로/네트워크 테스트 재통과 |
| AC-04 | PASS | 유료 1클릭·무료 회수 홀드·메뉴 입력 해제 경계 테스트 재통과 |
| AC-05 | PASS | 외곽 비활성·초기 중영 동일 ID 무료 회수·내곽 구매 테스트 재통과 |
| AC-06 | PASS (제출 비교 범위) | 기존 포함 전체1,671건 및 새 모드 초기360프레임의 greybox/sample 상태 비교 통과. 새 모드 전체 승패 주기의 양 렌더 모드 비교까지 입증한 것은 아님 |
| AC-07 | NOT RUN (release 요건) | 에디터 캡처34장은 존재하고 준비/결과 화면 검수. 요구된 release 캡처 미제출, R-02 |
| AC-08 | NOT RUN (구현 귀속) | 네 저장 측정의 수치·부하·구간 장부는 아래와 같이 통과. 검토 커밋에 대한 빌드 귀속 확인 미완, R-01 |
| AC-09 | PASS (전략 재현 증거) | 제출 비교 장부/도구에서 5전략의 승리·건설·회수 경로와 경제 비교 제공. 해당 장시간 비교 도구는 이번에 별도 재실행하지 않았으며 관련 회귀는 재실행 |

#### 성능 원시값 검산

| 시나리오 | frames | 평균 FPS | p95 ms | alive 최소 |
|---|---:|---:|---:|---:|
| full_move | 7530 | 125.496 | 23.818 | 1000 |
| full_combat | 7722 | 128.683 | 23.730 | 1000 |
| grow_move | 8412 | 140.197 | 20.527 | 1000 |
| grow_combat | 9454 | 157.547 | 19.201 | 1000 |

프레임/생존 배열 길이 일치, load_held_all_frames=true. 평균은 frame_us_raw 합계로, p95는 nearest-rank로 재계산. 네 파일은 동일 exe `b557ec69…cac25`, greybox, 종료 총수24다. 전체 p95 예산 판정이며 일부 구간의 p95>25ms를 숨기거나 전체 예산과 혼동하지 않는다. 상세 검산은 `results/evidence/wp-008/gpt-review/2026-09-20/perf_review.json`.

#### 기획 판단과 비차단 관찰

- **P-020:** 이번 회차의 비용/보상/HP 초기값은 유지. ‘무건설’은 아무 입력도 없는 런이 아니라 붕괴 후 무료 회수 배치를 포함한 전략이다. 해당 전략 승리를 곧바로 실패로 보지 않는다. 구매로 붕괴 지연/핵심 피해 개선이 확인되므로 기능 목적은 성립하며, 물자 잔여량만으로 비용을 올리기보다 WP-009 성문 공방에서 지출 시점·대응 기회를 다시 평가한다.
- 포화 골목의 유료 건설 거절은 명세대로다. 무료 회수 홀드 규칙을 유료 자동 재구매로 확대하지 않는다. 거절 이유·다른 배치 가능 위치 안내로 UX 보완을 제안한다.
- 기존 `--settings=`가 `--set` 접두어 분기에 걸리는 문제는 본 PR 이전부터 존재. 이번 결과의 ‘지정 임시 파일 사용’ 설명은 현재 파서와 불일치하므로 정정/수정 후 경로 검증 필요. 이번 기능의 신규 회귀로 분류하지 않는다.
- 경제 모드 초기6초 상태 비교 외에 붕괴/회수/종료/재시작의 양 렌더 모드 동일성 비교를 보강하면 후속 아트 통합 회귀 탐지에 유용하다.
- WP-009/010은 DRAFT 유지. R-01~03 보완 후 재리뷰하며 지금 DONE/PASS로 전환하지 않는다.

## 보완 회차 1 (2026-09-20, GPT 1차 REVISE → 재리뷰 요청)

- 보완 구현 커밋: **`8da6755`** ("fix(wp-008): GPT review R-01..R-03 …"). 이 절의 증거는 그 커밋의 깨끗한 트리에서 `verify.ps1 -Wp008`로 재생성했다(스크립트가 dirty 트리를 거절한다). 결과·증거 커밋: 이 문서의 커밋.
- 테스트: **1,683 passed / 0 failed (77.4 s)**, 종료 0 (R-03 회귀 3건 추가: 처치→웨이브→구매 seq 1,2,3·전 런 단조 증가·재시작 후 seq 1부터).

| 항목 | 조치 | 증거 |
|---|---|---|
| R-01 성능 증거의 구현 귀속 | 성능 4종을 깨끗한 커밋 `8da6755`에서 export한 release로 재실행. 네 JSON의 `manifest.implementation_sha` = `8da6755577558d5c5f8be9ffd80ba6c6ba3b5124`(dirty 아님), exe SHA-256 `7c103580f9cb…`(게임 자체 해시 = 외부 샘플러 해시). 이전 실행의 원시값은 `perf/run1_fail/`, `run2_fail/`와 git 이력(`2e1f401`)에 그대로 남고 SHA를 손대지 않았다. `verify.ps1 -Wp008`은 이제 dirty 트리에서 시작을 거절하고 JSON의 SHA가 HEAD와 다르면 실패한다 | 아래 성능 표, `perf/*.json` `manifest` |
| R-02 release 화면 | 캡처를 export한 exe로 실행(`build_out/.../hanyang_defense_wp001.exe -- --capture=wp008_build[_720] --art=greybox\|sample --sha=…`). greybox·sample × 1920×1080·1280×720 = 4런 × 17장. 각 로그 첫 항목 `capture_manifest`에 exe 해시(is_editor_binary false)·구현 SHA·아트 모드·로드된 리소스 수·설정 파일 경로·창 크기·config가 있다. sample 아트 위 건설 바·비용 고스트·회수 고스트·결과 경제 행 겹침은 Claude 육안으로 없음(가독성 판정은 GPT). 에디터 캡처 34장은 삭제(git 이력 `2e1f401`에 보존) | `captures/release_greybox/`, `captures/release_sample/` (PNG 68장 + 로그 4개) |
| R-03 구매 이벤트 seq | 구매 기록 키를 `purchase_seq`로 분리, `_event()`가 payload의 `seq`를 무시, `events_well_ordered()`를 스냅샷·캡처 로그·verify 검사에 추가. GPT 재현 스크립트(`gpt-review/2026-09-20/repro_event_seq.gd`) 순서는 이제 1,2,3 | 테스트 "Economy unit"(R-03), "AC-02 ledger", 캡처 로그 `econ_log.economy.events_well_ordered` |
| 관찰: `--settings=` 파서 | `--settings=`를 `--set` 접두어 검사보다 먼저 처리(이전에는 경로가 무시되고 `unknown config key: tings`가 찍혔다). release 캡처 로그의 `settings_path`가 전달한 임시 파일과 같은지 verify가 검사한다. 기존 WP-004 캡처 설명("임시 설정 파일 주입")은 이 수정으로 비로소 사실이 된다 | 캡처 manifest `settings_path` |
| 관찰: 양 렌더 모드 전체 주기 비교 | 캡처 스크립트에 `state_log` 체크포인트 8개(준비 시작·준비 구매·t20·붕괴·회수·내곽 구매·결과·재시작)를 넣고 verify가 greybox/sample × 1080p/720p 4런의 `state_hash`를 대조한다 → 체크포인트 8/8 전부 동일 | 로그 `state_log`, verify 출력 |
| P-020 | GPT 판단(초기값 유지, WP-009에서 재평가) 확인. 수치 변경 없음 | — |

### 성능 (보완 회차 1, release `7c103580f9cb…`, 구현 `8da6755`, 보이는 창, greybox)

| 시나리오 | 프레임 | 생존 min / avg | 평균 FPS | 프레임 ms p50 / **p95** / p99 / max | 구간 [0,20) / [20,25) / [25,60] avg FPS · p95 | 창 안 구매 ok / 상한 거절 | 배치 · pv | 워킹셋 MB | 판정 |
|---|---:|---|---:|---|---|---|---|---|---|
| build_full_move | 8,837 | 1000 / 1000.0 | **147.3** | 4.37 / **20.87** / 23.87 / 36.36 | 118.3·22.83 / 168.1·19.99 / 160.9·20.11 | 0 / 1 | ok · pv 4→5 | 181.2→193.6 | PASS |
| build_full_combat | 9,708 | 1000 / 1000.0 | **161.8** | 3.65 / **19.36** / 22.21 / 35.50 | 132.4·21.05 / 177.6·18.92 / 176.3·18.67 | 0 / 1 | ok · pv 4→5 | 181.6→133.6 | PASS |
| build_grow_move | 10,778 | 1000 / 1000.0 | **179.6** | 3.58 / **17.19** / 19.43 / 26.29 | 157.8·18.03 / 198.1·16.55 / 189.5·16.82 | 2 / 1 | ok · pv 4→6 | 180.9→142.2 | PASS |
| build_grow_combat | 11,570 | 1000 / 1000.0 | **192.8** | 3.24 / **16.10** / 18.25 / 25.18 | 169.3·17.11 / 209.8·15.70 / 203.8·15.63 | 2 / 1 | ok · pv 4→6 | 181→133.3 | PASS |

### release 캡처 (보완 회차 1)

| 아트 | 시나리오 | 실행파일 | 구현 SHA | 모드 | 리소스 | 클릭 구매 | 결과 | 체크포인트 vs greybox 1080p |
|---|---|---|---|---|---|---:|---|---|
| greybox | wp008_build | `7c103580f9cb…` (release: is_editor False) | `8da6755` | greybox | — | 6 | WON / 잔액 1093 | 8/8 동일 |
| greybox | wp008_build_720 | `7c103580f9cb…` (release: is_editor False) | `8da6755` | greybox | — | 6 | WON / 잔액 1093 | 8/8 동일 |
| sample | wp008_build | `7c103580f9cb…` (release: is_editor False) | `8da6755` | sample | 17/35 로드 | 6 | WON / 잔액 1093 | 8/8 동일 |
| sample | wp008_build_720 | `7c103580f9cb…` (release: is_editor False) | `8da6755` | sample | 17/35 로드 | 6 | WON / 잔액 1093 | 8/8 동일 |

- Claude 육안 관측(sample 아트, 판정 아님): 1280×720에서 붉은 거절 고스트 문구("물자 부족: 화차 100 필요 · 잔액 40")가 광장 바닥 위에서 가늘게 보인다(1080p·greybox는 충분). 문구 배경판 추가는 D-053 V-01(기본 표시 정리)과 함께 다루는 편이 맞아 이번 회차에는 바꾸지 않았다. 건설 바·HUD·결과 경제 행은 두 해상도 모두 겹침 없음.
- AC 재판정(구현자): AC-07 **PASS**(release 두 해상도·두 아트 모드, exe 해시·구현 SHA 연결), AC-08 **PASS**(깨끗한 커밋 귀속, 예산 충족), AC-02 R-03 해소, AC-06 전체 주기 양 모드 비교 추가. 나머지 PASS 유지. 재미·균형·가독성 판정은 GPT.

## 사용자 요청 추가 (2026-09-24): 건설 고스트의 표적 존 표시

- 요청: "건설 고스트에 표적 존 여부 표시". 구현 커밋 **`28be613`**, 이 절의 증거는 그 커밋의 깨끗한 트리에서 `verify.ps1 -Wp008`로 다시 만들었다(보완 회차 1의 수치는 git 이력 `e431cd5`에 보존). 재리뷰 대상 HEAD가 이 커밋으로 바뀐다.
- 배경: 화차는 적 개체가 아니라 표적 존의 중심을 겨누고, 자기 100 px 또는 같은 봉수망 혼천의가 본 적만 센다. 그래서 사거리 안에 존이 없거나, 존이 있어도 탐지 수단이 없으면 적을 보고도 쏘지 않는다. 기존 고스트는 이 사실을 보여 주지 않았다(T-09, E-08).
- 구현: `Battle.hwacha_placement_hint()`(읽기 전용, 표적 선택·봉수망 부착과 같은 규칙) → 고스트에 사거리 원, 사거리 안 존 테두리(청록 직접 / 주황 공유 / 빨강 탐지 없음), 연결될 봉수대, 탐지 가능한 존이 없으면 "쏘지 않는다" 경고. sandbox 설치 고스트에도 같은 표시. 규칙·수치 변경 없음.
- 한계: 겹침은 필요조건이다. 예를 들어 (40,20)은 광화문 앞 존(Z9)이 "직접"으로 나오지만 적은 붕괴 뒤에만 Z9에 들어온다. 고스트는 웨이브 경로까지 예측하지 않는다.
- 테스트: **1,713 passed / 0 failed** (새 검사 16건: 7개 자리에서 힌트 존 == 표적 후보, 예측 부착 == 실제 부착, 존 없음·탐지 없음 화차는 45 s 동안 0발이고 탐지 가능한 화차는 발사, 봉수대·혼천의 구매로 탐지 없음 → 공유 전환, 조회가 전투 상태를 바꾸지 않음, 캡처 로그 기록).

| 캡처 자리 (release, greybox) | 사거리 안 존 | 탐지 가능 존 | 고스트 문구 |
|---|---:|---:|---|
| (31, 17) | 0 | 0 | 주의: 사거리 200 px 안에 표적 존 없음 — 적을 봐도 쏘지 않는다 · 봉수 연결 없음 — 직접 탐지 100 px만 |
| (37, 27) | 1 | 0 | 주의: 사거리 안 표적 존 1개를 탐지할 수단이 없어 쏘지 않는다 — Z8 광장 남단(탐지 없음) · 봉수 연결 없음 — 직접 탐지 100 px만 |
| (40, 20) | 3 | 1 | 표적 존 3(탐지 1): Z7 광화문 어귀(탐지 없음), Z8 광장 남단(탐지 없음), Z9 광화문 앞(직접) · 봉수 연결 없음 — 직접 탐지 100 px만 |

- 캡처: `captures/release_{greybox,sample}/wp008_build[_720]_02_preview_hwacha_cost.png`, `_02b_no_target_zone.png`, `_02c_zone_not_detectable.png` (release exe `45fc7311aa11…`, 구현 `28be613`). 기존 17장과 8개 체크포인트 동일성 검사는 그대로 통과.
- 관측(Claude 육안, 판정 아님): 1080p에서는 사거리 원·존 색·문구가 잘 읽힌다. 720p에서는 원과 색은 분명하지만 한 줄 문구가 작다(약 9 px). 문구 크기·줄 나눔은 D-053 V-01(기본 표시 정리)에서 함께 다루는 편이 맞다.

| 성능 (release, 보이는 창, greybox) | 평균 FPS | p95 ms | alive min | 구현 SHA |
|---|---:|---:|---:|---|
| build_full_move | 153.1 | 19.61 | 1000 | `28be613` |
| build_full_combat | 159.8 | 19.11 | 1000 | `28be613` |
| build_grow_move | 185.8 | 16.32 | 1000 | `28be613` |
| build_grow_combat | 195.8 | 15.58 | 1000 | `28be613` |
