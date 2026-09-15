# WP-003 Result

- 작성일: 2026-09-15
- WP / 상태: WP-003 검증·붕괴·후퇴·재편 / **DONE** (GPT 2026-09-15 1차 **REVISE** `f379bea` → 보완 회차 `41ff91c`/`1598d23` → **재리뷰 2차 PASS 8/0/0** `f5d7e69` — 문서 끝 GPT 재리뷰 절. DONE 전환 2026-09-15, Claude Code). 1차 회차의 HP 120 결과(F1 FAIL)는 아래에 그대로 보존한다. PR #4 병합은 사용자 지시에 따른다.
- 기준 커밋: `31193a3` ("docs(wp-003): finalize fixtures and acceptance criteria, mark READY", main)
- 검증한 구현 커밋: `7fc75ab` ("feat(wp-003): …") → **Codex 리뷰 반영 `6e9240c`** ("fix(wp-003): scripted scenarios reapply every mode key; held click follows run mode; quit-after on run end; no stale goal marker"). 게임 코어(`game/core/`)는 두 커밋에서 동일하며 변경은 `game/scenes/`뿐이다.
- 브랜치: `wp/003-collapse-retreat` · PR: https://github.com/darkrunar/hanyang-defense/pull/4 (GPT PASS, 병합은 사용자 지시 대기)
- 실행 환경 / 엔진·버전: Godot 4.7.stable.official.5b4e0cb0f (GDScript, 2D, gl_compatibility / OpenGL 3.3) · Windows 11 Home 10.0.26200 · AMD Ryzen 5 7600 (6C/12T) · NVIDIA GeForce RTX 4070 SUPER (driver 591.86) · 63.2 GB RAM · 1920×1080 · Parsec 가상 디스플레이 어댑터 공존(vsync off로 측정)

이 문서는 `results/RESULT_TEMPLATE.md` 양식을 따른다. 수치는 전부 `results/evidence/wp-003/` 원시 파일에서 가져왔고, WP-001/002 증거와 사전 검토 증거(`wp-003/pre-review/`)는 손대지 않았다. 문서 커밋은 구현 커밋과 분리한다.

## 구현 결과

계약 문서는 [backlog/WP-003.md](../backlog/WP-003.md) READY v1.0(D-019~027)이다. **HP·웨이브·합격선·좌표를 바꾸지 않았다.** 구현자가 결정한 자료구조·모드 격리는 D-028~031에 기록했고, 구현 중 발견한 두 항목(F1 불성립 P-017, 스위트 종료 코드 P-018)은 제안으로 남겼다.

### 변경 파일과 각 변경 목적

| 파일 | 목적 |
|---|---|
| `game/core/run_state.gd` (신규) | 런 RUNNING/WON/LOST·방어 OUTER_ACTIVE/INNER_ONLY, 외곽/핵심 HP(0에서 멈춤, 초과 미전달), 붕괴 1회·회수권 1·run_id, 틱+순번 이벤트 로그, 벤치마크 전용 핵심 무적(시도량 집계) |
| `game/core/wave_director.gd` (신규) | 유한 3웨이브(60/60/60, 120/120/120, 360/120/120 @ 10/10/10, 30/10/10 체/초), 고정 틱 누산기, 남→서→동 순서, 예산 소진+생존 0 후 5초 간격, 마지막 웨이브 완료 플래그, 시나리오 추가 생성 별도 집계 |
| `game/core/enemy_sim.gd` | `arrival_mode` immediate(WP-001/002 그대로) / after_fire(WP-003: 목표 반경 안 대기 → 사격 후 `collect_arrivals()`가 생존 개체만 1회 소비, 도달=누수·처치 아님), `spawn_on_route()`(진입로별 안정 셀 순환), `rng_state()` |
| `game/core/placement.gd` | 구역 규칙(footprint 단일 구역 `DISTRICT_SPLIT`, 붕괴 후 외곽 `DISTRICT_LOST`, 회수는 내곽만 `WRONG_DISTRICT`), `detach()/restore()`(같은 객체·같은 ID, 분리 중 목록 제외로 탐지·부착·사격·쿨다운 감소 없음), `preview_restore()`, `RUN_ENDED`/`NO_RECOVERY_RIGHT`/`NOT_DETACHED` |
| `game/core/battle.gd` | WP-003 틱 순서(생성→이동→밀도/망/탐지→사격→생존 도달·거점 피해→붕괴→승패→벤치마크 보충), 붕괴 처리(H1 분리·회수권·외곽 일괄 비활성(장승 차단 유지)·외곽 잠금·핵심 목표 전환 경로 재계산 1회·망 갱신), `place_recovery()`(성공 시에만 권리 소비), `restart()`(run_id+1), 검증 전용 `force_outer_hp/force_core_hp/spawn_extra`(로그), `state_hash()`, 경로 버전 재기준화(D-031) |
| `game/core/config.gd` | `zone_set`, `arrival_mode`, `run_mode`, `district_rules`, `outer_hp` 120, `core_hp` 60, `arrival_damage` 1, `wave_gap_seconds` 5, `benchmark_core_invulnerable`; `Config.for_wp003()` 프리셋(기본값 `Config.new()`은 WP-002 sandbox 그대로) |
| `game/maps/hanyang_test_map.gd` | WP-003 데이터: 외곽 (47,26)/핵심 (47,10), 내곽 x42~53/y6~22, Z8/Z9, fixture C 장승 J1 (44,36)/J2 (22,24), 회수 A (52,12)/B (44,13), 웨이브 표, F3 생성점 (950,450)·12체, `district_of_cell()` |
| `game/scenes/main.gd` | 기본 플레이 = WP-003 런; waves 모드에서 LMB=회수 배치(유효성 고스트·거절 사유 한글), R=재시작, 자유 설치/철거/T/C 비활성; HUD(런/방어 상태·양 거점 HP·도달·웨이브·회수 안내·종료 배너); `--capture=wp003_f2`; `--perf --scenario=collapse_move|collapse_combat`(D-027: 측정 20초 트리거·25초 배치 B, 구간 통계, 의미 이벤트 6건, 스냅샷 5개, manifest) |
| `game/scenes/overlay_layer.gd` | 내곽 테두리·붕괴 후 외곽 음영, 두 거점 마커+HP 바(현재 목표 강조), 회수 대기 H1 표시(동결 쿨다운), 회수 배치 고스트(사유 표시), 스크립트 미리보기 오버라이드 |
| `game/tools/wp003_timeline.gd` (신규) | F1 초 단위 장부(웨이브 상태·생존·처치·도달·HP·화차별 발사)와 이벤트 JSON |
| `game/tools/perf_recorder.gd` | `last_frame_us` 노출(구간 통계용) |
| `tests/test_collapse_retreat.gd` (신규), `tests/run_tests.gd` | setup·AC-01~03·F1~F4 + 재시작 결정성 (WP-003 절 192건 중 187 PASS / 5 FAIL = F1) |
| `scripts/verify.ps1`, `verify.sh`, `perf_with_memory.ps1` | 4c(F1 타임라인·F2 캡처)·6c(전환 성능, D-027 계약 검사: 6 이벤트·구간별 평가>0·배치 ok·트리거→붕괴 ≤2틱·자연 붕괴 없음·pv 기대+1), collapse 시나리오 허용 |
| `docs/DECISIONS.md`, `README.md`, `docs/ROADMAP.md`, `backlog/WP-003.md` | D-028~031, P-017/018, WP-003 실행·조작 절, 상태 REVIEW |

## 실행·재현 절차

필요 도구: Godot 4.7.stable(`godot` PATH), Windows export template(빌드·성능), PowerShell(성능 메모리 샘플러). 추가 패키지 없음.

```bash
git clone https://github.com/darkrunar/hanyang-defense.git && cd hanyang-defense && git checkout wp/003-collapse-retreat
```

| 단계 | 명령 | 산출물 |
|---|---|---|
| 자동 검증(WP-001/002 회귀 + WP-003) | `godot --headless --path . --script res://tests/run_tests.gd -- --report=<abs>/results/evidence/wp-003/tests/test_report.txt` | **종료 코드 1**: 509 passed / 5 failed — 실패 5건 전부 F1(P-018) |
| F1 타임라인 | `godot --headless --path . --script res://game/tools/wp003_timeline.gd -- --out=<abs>/results/evidence/wp-003/tests/f1_timeline.json` | 초 단위 장부 + 이벤트 |
| F2 캡처 | `godot --path . --rendering-driver opengl3 -- --capture=wp003_f2 --out-dir=<abs>/results/evidence/wp-003/captures` | PNG 7장 + `wp003_f2_log.json` |
| 릴리스 빌드 | `godot --headless --path . --export-release "Windows Desktop Release" build_out/windows/hanyang_defense_wp001.exe` | 단일 exe |
| 전환 성능 | `.\scripts\perf_with_memory.ps1 -Scenario collapse_move\|collapse_combat -Warmup 10 -Measure 60 -Out results\evidence\wp-003\perf\perf_<sc>_1000_release.json` | 프레임 JSON(원시 배열·구간·이벤트·스냅샷·manifest) + `.memory.json` |
| 일괄 | `.\scripts\verify.ps1` / `scripts/verify.sh` | 1단계(테스트)에서 F1 FAIL로 중단됨(P-018). 위 단계별 명령으로 증거 생성 |
| 플레이 | `godot --path . --rendering-driver opengl3` | 기본 WP-003 런. 조작은 README |

설정: 시드 `20260913`, 고정 스텝 60 Hz, 외곽 HP 120 / 핵심 HP 60 / 도달 피해 1 / 목표 반경 26px, 적 HP 60·속도 58±22%, 화차 피해 34/재장전 0.8s/폭발 55/사거리 200/로컬 100/센서 140/연결 180 — 계약값 그대로. F3는 `enemy_speed_jitter=0`, `enemy_lane_offset=0`, H4 비활성, 웨이브 끔. 성능은 `benchmark_hold_alive`·`benchmark_core_invulnerable`·외곽 HP 1,000,000(트리거까지)·웨이브 끔 — manifest에 공개.

## Acceptance Criteria

| AC | PASS / FAIL / NOT RUN | 기대 결과 | 실제 결과 | 증거 파일·로그·화면 |
|---|---|---|---|---|
| AC-01 | **PASS** | 실제 피해로 붕괴 1회, 초과 피해 핵심 미전달, 회수권 1 | 외곽 HP 1 + 도달 3체 → 피해 1(초과 2 폐기), 핵심 60 유지, 붕괴 1·이벤트 1·회수권 1·INNER_ONLY·목표 핵심·경로 버전 +1·H1 분리·외곽 13 비활성(점유 유지)·내곽 4 활성·장승 2 유지·세 경로 핵심 도달. 이후 핵심 도달 2 → 핵심 58, 붕괴 수·회수권 불변. 도달 위치에서 사격으로 죽은 적(HP 1)은 피해 0, 생존 도달은 정확히 1 | `wp-003/tests/test_report.txt` "AC-01" 2케이스 28건; F2 캡처 로그 이벤트 |
| AC-02 | **PASS** | 생존/신규 적이 핵심으로, ID·좌표·HP 보존, 모든 경로 유지 | 붕괴 틱에 비행 중 5체 ID·HP 보존, 이동량 ≤ 1틱(순간이동 없음), 이후 핵심 도달/처치로 소진(외곽 추가 도달 0), 신규 생성도 핵심 목표, target_changed 1건, path_version 정확히 +1 | 테스트 "AC-02" 19건 |
| AC-03 | **PASS** | 외곽 기능 중단·H1만 동일 ID로 1회 배치·쿨다운 보존 | 붕괴 전 회수 `NO_RECOVERY_RIGHT`; 붕괴 후 비활성 외곽 화차 발사 0·인지 0, 간선은 B2–B3 1개; 거절 `DISTRICT_LOST`(46,29)·`DISTRICT_SPLIT`(41,18)·`TERRAIN_BLOCKED`·`STRUCTURE_OVERLAP`(S4 위)·`ENEMY_OCCUPIES_CELL` 모두 권리·시설 수 불변, 미리보기 일치; 외곽 재활성·외곽 신설 거절; B 배치 성공 → 같은 객체·ID 1·발사 수·쿨다운 보존·B2 부착·S4와 같은 그룹, 권리 0, 재배치 `NO_RECOVERY_RIGHT`, 화차 4 유지. 분리 H1 쿨다운 0.5 → 2초 후 0.5 동결, 비활성 H2 0.5 → 0.0 감소(현행 유지), 배치 후 재개 | 테스트 "AC-03" 2케이스 54건; 캡처 c/d/e |
| AC-04 | **PASS** | F3 A/B 사전 합격선 | 같은 스냅샷(state_hash 동일) 후 A/B 배치 성공, A 미부착/B B2 부착, 첫 인지에서 S4가 12체 전부 관측, A/B 로컬 0, B의 Z9 인지 12 / A 0. 관측 30초: **B 공유전용 사격 1, 처치 B−A = 12−0, 핵심 피해 A−B = 12−0, B 핵심 HP 60 > 0** (합격선 ≥1 / ≥6 / ≥6) | 테스트 "F3" 16건 |
| AC-05 | **FAIL (F1) / PASS (F2·F4)** | F1 외곽 유지 승리, F2 붕괴 후 승리, F4 최종 패배 | **F1 FAIL**: 입력·강제 피해 없이 **LOST at 92.2 s** — W1 도달 66/180(외곽 120→54), W2 중 **52.8초 자연 붕괴**, W3에서 핵심 0(도달 61), 처치 695, 생존 264. 아래 분석·P-017. **F2 PASS**: 20초 강제(외곽 HP 1 + 실제 도달) → 붕괴 tick 1200, +5초(tick 1500) B 배치 성공(핵심 60), **WON 105.5초** INNER_ONLY 핵심 HP 28, 생성 1141(=1140+1), 생존 0; +0/+10초 배치도 성공(핵심 60/59). **F4 PASS**: 핵심 HP 1 + 마지막 적 도달 → 같은 틱 alive 0·핵심 0 → **LOST 우선**; 도달 위치 사격 처치 대조군 피해 0 | `test_report.txt` "F1"(5 FAIL)·"F2"·"F4"; `tests/f1_timeline.json`; 캡처 `wp003_f2_*` 7장 + 로그 |
| AC-06 | **PASS** | 종료 후 120틱 불변·명령 거절·재시작 초기화·결정성 | LOST/WON 각각 120틱 state_hash 불변·틱 미진행, 회수/설치/철거/활성 `RUN_ENDED` 거절, 재시작 후 run_id+1·HP·18시설·회수권 0·적 0·웨이브·목표·이벤트 로그 초기화·전원 활성, 재시작 런 = 새 런 state_hash 동일 | 테스트 "F4" 33건 |
| AC-07 | **PASS** | WP-001/002 회귀 + collapse_move/combat D-009·D-027 | WP-001/002 회귀 **322/322 동일**(wp001/sandbox 모드; Codex 지적 후 legacy 시나리오가 sandbox 프리셋을 전부 재적용함을 짧은 perf 실행과 ac02/wp002_a 캡처 재현으로 확인). 전환 성능 **회차 3(`6e9240c` 빌드)**: **collapse_move 219.5 FPS / p95 12.86 ms, collapse_combat 245.9 FPS / p95 11.61 ms**, 전 프레임 alive ≥1000, 의미 이벤트 6건·순서 정상, 트리거→붕괴 0틱, 붕괴→배치 299/300틱, 배치 1회 성공, 경로 버전 기대+1, 세 구간 후보 평가 >0, combat 배치 후 H1 9발. 회차 1 무효(부하 미유지)·회차 2(`7fc75ab`)는 참고로 보관. 아래 표 | `wp-003/tests/test_report.txt`; `wp-003/perf/perf_collapse_*_1000_release.json`, `*.memory.json` |
| AC-08 | **PASS** | 화면·JSON·조작 안내·새 체크아웃 재현 | F2 캡처 7장: 외곽 방어(HP 114/120·도달)·붕괴 알림(회수 1/1·내곽 테두리·외곽 음영)·외곽 미리보기 거절(`DISTRICT_LOST`)·내곽 유효 미리보기·배치 완료(부착 6·hover 패널)·내곽 사격·승리 배너. README·이 절·`scripts/verify.*`(4c/6c). 결정성 테스트 | `wp-003/captures/`, README |

자동 검증 합계: **509 passed / 5 failed**(실패 5건 = F1) + WP-001/002 회귀 322/322 포함. 스위트 종료 코드 1은 의도된 정직 보고(P-018).

### F1 FAIL 분석 (`tests/f1_timeline.json`)

| 구간 | 생성 누계 | 처치 | 외곽 도달 | 외곽 HP | 비고 |
|---|---|---|---|---|---|
| W1 종료(~30초) | 180 | 114 | 66 | 54 | 골목 존 통과 ~1.5초에 볼리 1~2발(처치엔 2발 필요), 광장 수렴 후엔 Z8 한 곳만 사격 |
| W2 중 52.8초 | 540 | ~353 | 120 | **0 → 붕괴** | 자연 붕괴. 이후 목표 핵심 |
| W3(75~92초) | 1140 | 695 | — | — | 핵심 도달 61 → **핵심 0, LOST 92.2초**, 생존 264 |

- 구현 결함이 아니라 계약 수치의 밸런스 결과다: 18시설(외곽 화차 3)로 초당 30체 유입(W1)을 막지 못한다. 수치를 통과 목적으로 바꾸지 않았다(계약 "임의 변경 금지").
- 대조: **F2에서 20초에 강제 붕괴시키면 오히려 승리(핵심 HP 28)** — 광화문 4셀 병목에 궁성+회수 중영이 집중되는 내곽 방어가 넓은 외곽 방어보다 강하다. "후퇴가 유리한" 구조는 CORE_LOOP의 "붕괴의 의미"와 부합하나, F1의 "외곽 유지 승리도 허용"은 현재 수치로는 성립하지 않는다.
- 제안(P-017, 기획 판단): (a) 외곽 HP 상향, (b) W1/W2 생성 속도 하향, (c) 광장 접근 존 추가·외곽 화차 재배치, (d) F1 합격 조건 완화("붕괴 후 승리"까지 허용). 어느 쪽이든 GPT 결정 후 재측정.

## 성능

- OS / CPU / GPU / RAM / 해상도 / 빌드 설정: 위 실행 환경. `exported release`, x86_64, pck 내장, gl_compatibility, 창 1920×1080, vsync 0.
- 시나리오: fixture C(18시설·10존·시드 20260913), `run_mode=waves`이나 웨이브 끔, `benchmark_hold_alive`(매 틱 끝 1,000 보충), 외곽 HP 1,000,000 → 측정 20초 첫 틱에 검증용 1로 설정 + 정상 적 1체를 외곽 거점에 생성(실제 도달로 붕괴), 측정 25초 첫 틱에 회수 배치 B(1회 시도, 거절이면 FAIL), `benchmark_core_invulnerable`(시도량 집계). 10초 준비 + 60초 측정, Esc 외 입력 무시. 구현 SHA는 `--sha`로 manifest에 기록.

| 회차 | 시나리오 | 프레임 / 초 | 생존 min / avg / max | 부하 유지 | 평균 FPS | 프레임 ms p50 / **p95** / p99 / max | sim step ms avg / p95 / max | 구간 [0,20) / [20,25) / [25,60] avg FPS · p95 · max · 평가 | 이벤트·전환 | 워킹셋 MB 시작→종료 (최대) | 종료 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **3 (채택, `6e9240c`)** | collapse_move | 13,173 / 60.01 | **1000 / 1000.0 / 1001** | true | **219.5** | 2.69 / **12.86** / 16.90 / 27.81 | 3.86 / 7.43 / 11.42 | 159.3·16.52·27.81·4,800 / 254.4·12.16·25.31·302 / 249.0·12.02·20.69·4,200 | 6건 tick 1805(trigger·collapse·recovery_created·outer_deactivated·target_changed) + recovery_placed 2104; 트리거→붕괴 0틱, 붕괴→배치 299틱, 배치 ok(1회), pv 4→5, 위상 v16→v18, 핵심 흡수 2,072(무적) | 176.2→183.2 (183.2) | 0 |
| **3 (채택, `6e9240c`)** | collapse_combat | 14,757 / 60.01 | **1000 / 1000.0 / 1001** | true | **245.9** | 2.54 / **11.61** / 13.77 / 37.37 | 2.36 / 4.07 / 6.77 | 209.1·12.95·37.37·2,500 / 269.6·11.21·17.48·78 / 263.6·11.22·20.05·85 | 6건 tick 1805 + recovery_placed 2105; 트리거→붕괴 0틱, 붕괴→배치 300틱, 배치 ok(1회), pv 4→5, 위상 v16→v18; 구간 발사 138(공유전용 44: 붕괴 전 43·대기 1·배치 후 0), **배치 후 H1 9발**(총 75발·1,871처치), 핵심 흡수 11 | 178.4→181.5 (181.5) | 0 |
| 2 (참고, `7fc75ab`) | collapse_move | 12,468 / 60.01 | 1000 / 1000.0 / 1001 | true | 207.8 | 3.08 / 13.19 / 17.21 / 44.33 | 4.06 / 8.48 / 9.59 | 153.9·16.41·44.33·4,804 / 248.7·11.89·18.00·303 / 232.7·12.47·27.50·4,200 | 동일 6건, 배치 2106, 계약 충족. Codex 수정 전 빌드라 참고(`*_run2_pre_codex.json`) | 180.4→183.1 | 0 |
| 2 (참고, `7fc75ab`) | collapse_combat | 14,487 / 60.00 | 1000 / 1000.0 / 1001 | true | 241.4 | 2.68 / 11.60 / 14.06 / 20.65 | 2.51 / 4.83 / 7.00 | 201.4·13.17·19.56·2,500 / 263.9·11.09·20.65·80 / 261.1·11.08·16.96·85 | 동일 6건, 배치 2105, H1 배치 후 9발. manifest SHA는 문서 커밋 `2322a62`(게임 트리 동일) | 172.7→181.2 | 0 |
| 1 (무효, 보관) | collapse_move / combat | — | **0 / 0 / 1** | **false** | 275.1 / — | — | — | — | perf 모드가 프리셋 전체를 복사해 `benchmark_hold_alive`가 꺼짐(수정됨). 부하 조건 미충족 → 무효. `perf/*_run1_hold_off.json` | — | 0 |

- 예산 대비(회차 3): 평균 60 FPS 이상 → **219.5 / 245.9 (통과)**, p95 25 ms 이하 → **12.86 / 11.61 ms (통과)**, 모든 기록 프레임 alive ≥1000 → `alive_raw` 전 원소 ≥1000 (통과, 트리거 적 1체로 최대 1001). 원시 배열 길이 = frames, 모든 간격 > 0, 합계 60.01 s, 재계산 FPS 219.5 / 245.9, p95 12.861 / 11.605 ms — 저장값과 일치.
- D-027 이벤트: `benchmark_trigger` → `collapse` → `recovery_created` → `outer_deactivated_batch` → `target_changed`(같은 틱, 순번으로 구분) → `recovery_placed`, 각 1건, 실패 이벤트 0(`recovery_refused` 없음). 자연 붕괴 0(트리거 전 `collapse_count` 0). 스냅샷 5개(measure_start / before_trigger_20s / after_collapse / after_placement_25s / end): 시설 18→17(대기 1)→18, 활성 18→4→5, 구역 내곽 5 활성 / 외곽 13 비활성.
- 출처(회차 3): 실행 파일은 Codex 반영 커밋 `6e9240c` 트리에서 export, 두 manifest `implementation_sha` 모두 `6e9240c`, `-dirty` 없음. 회차 2 출처는 표의 비고 참조.
- 정직 기록: collapse_move의 붕괴 전 구간(0~20초)은 평균 159.3 FPS / p95 16.52 ms / 최대 27.81 ms(회차 2: 153.9 / 16.41 / 44.33)로 다른 구간보다 무겁다 — 외곽 목표 단계에서 1,000체가 광장 남단(Z8)에 수렴하며 화차 4대가 매 틱 후보를 평가하는 비용(sim step 평균 4.06 ms). 예산 안이지만 WP-002에서 기록한 "이동 시나리오 후보 계산 비용" 항목의 연장선이다. 단발 최대 스파이크(회차 3 combat 37.37 ms, 회차 2 move 44.33 ms)는 원인 미측정(프레임 시간 이봉 분포와 함께 미해결).
- 벤치마크 전용 설정은 정상 승패 증거에 쓰지 않았다(F1/F2/F4는 보호·보충 없음).

## 실제 화면 확인

`--capture=wp003_f2`(6배속, 절대 시각)가 지정 시각에 PNG와 상태 JSON을 남긴다.

| 캡처 | 관측 |
|---|---|
| `wp003_f2_a_outer_defense_t15.png` | W1 방어 중: 외곽 HP 114/120(도달 6), 핵심 60, 생존 62, 세 진입로 흐름, 외곽 거점 마커·HP 바 "현재 목표" |
| `wp003_f2_b_collapse_notice_t20.5.png` | 붕괴 직후: HUD "내곽 방어 (외곽 붕괴)", 외곽 HP 0/120, **"▶ 붕괴! 화차·중영 회수 1/1"**, 내곽 노란 테두리·외곽 음영, 우측 회수 대기 마커(재장전 0.80s 동결·발사 19·처치 57), 외곽 시설 회색, 핵심이 현재 목표 |
| `wp003_f2_c_invalid_outer_preview_t23.png` | 외곽 (46,29) 미리보기 → 빨간 고스트 `DISTRICT_LOST` |
| `wp003_f2_d_valid_inner_preview_t23.5.png` | 내곽 B (44,13) 미리보기 → 초록 고스트 "배치 가능" |
| `wp003_f2_e_recovery_placed_t25.5.png` | 배치 완료 0/1 @(44,13) 부착 6, hover 패널(부착 봉수대 6·그룹 6·로컬 1+공유 4·재장전 0.30s), B2 부착선 |
| `wp003_f2_f_inner_fire_t45.png` | W2 중 내곽 사격: 중영·궁성이 Z7/Z9 표적, 핵심 HP 59 |
| `wp003_f2_g_run_end.png` | **"WON — 승리, 핵심 시설 사수 (R 재시작)"**, 핵심 28/60(도달 32), 생성 1141·처치 1073·생존 0, 중영 84발/59처치·궁성 71발/957처치 |

## Codex 자동 리뷰 반영 (PR #4, `6e9240c`)

| 지적 | 조치 |
|---|---|
| legacy 시나리오(move/combat/network_*/ac0*)가 WP-003 기본 모드 키(run_mode waves·after_fire·구역·10존)를 물려받음 (P1) | `_apply_mode_preset()`이 모드 키 전부(targeting/fixture/zone_set/arrival/run_mode/district/HP/피해/간격/무적)를 시나리오 프리셋에서 재적용. 짧은 perf 실행으로 move/network_move가 sandbox·immediate·8존·alive_min 1000임을 확인, ac02/wp002_a 캡처 상태값 재현(경로 버전 절대값만 D-031 재기준화로 −1, 델타 동일; 승인된 WP-001/002 증거 파일은 덮어쓰지 않음) |
| 회수 거절 후 홀드 클릭이 자유 장승 설치로 빠짐 (P1) | 홀드 재시도도 run_mode로 분기 |
| 런 종료 후 `--quit-after`가 영원히 대기 (P2) | 런 종료 시에도 종료 |
| 지형 레이어의 정적 목표 마커가 외곽과 겹치고 붕괴 후 오래됨 (P2) | waves 모드에서 정적 마커 끔(오버레이가 두 거점을 상태와 함께 그림). F2 캡처 7장 재생성 |

## 미해결 문제와 설계 변경 제안

1. **P-017 F1 불성립** — 위 분석. 기획 결정 필요(HP/속도/존/합격 조건).
2. **P-018 스위트 종료 코드 1** — F1 5건이 FAIL이라 `run_tests.gd`가 1을 반환하고 `verify.*` 1단계에서 멈춘다. 실패를 숨기지 않기 위해 유지; F1 판정이 바뀌면 자동 해소.
3. **Z9 경계** — 계약대로 r50 유지. S4→Z9 반대편 가장자리 140.55px는 미관측 가능(개체별 관측만 보장). F3의 12체는 (950,450)이라 전부 관측됨(테스트 단언).
4. **회수 배치 점유 거절 위험** — F2 +5초 배치는 B (44,13)에서 성공했고 +0/+10초도 성공. 1,000체 벤치마크에서의 결과는 성능 표 참조.
5. **캡처 시나리오 시각** — 절대 시각(20.0/25.0)을 쓰며 붕괴는 트리거 다음 틱(tick 1200)에 일어난다(결정적). 다른 시드에서는 조정 필요.
6. 이전 WP의 미측정 항목(프레임 시간 이봉 분포, 이동 시나리오 후보 계산 비용)은 그대로다.

## 다음 WP 영향

- 재사용: `RunState` 이벤트 로그(틱+순번)는 경제·캐릭터 WP의 사건 기록 기반이 된다. `detach/restore`는 시설 이동·회수 비용 도입 시 그대로 쓰인다(권리 소비 지점만 경제 규칙으로 교체). `WaveDirector`는 웨이브 표만 데이터로 바꾸면 된다.
- 인터페이스: 구역은 `district_of_cell` 콜백 하나(맵 데이터)라 다구역 확장 가능. 목표는 여전히 하나(`PathNetwork.goal`) — 다중 목표/구역별 목표는 경로장 다중화가 필요.
- 주의: WP-003 기본 플레이에서 자유 설치를 껐다(계약). 경제 WP에서 다시 열 때 `district_rules`·`locked_district`가 그대로 적용된다. after_fire 도달 모드는 wp003 프리셋에서만 켜진다.

## PR

- PR #4: https://github.com/darkrunar/hanyang-defense/pull/4 · 구현 `7fc75ab` · 결과·증거 `2322a62` + 성능 보완 커밋(이 문서의 커밋)

## GPT Review

- 검토일 / 검토한 구현 커밋: (PENDING) / `6e9240c` (코어는 `7fc75ab`와 동일)
- 최종 판정: **PENDING**
- 기준별 검토 결과: (PENDING)
- 범위 준수 / 기획 일치 / 증거 충분성: (PENDING)
- 보완 요청 또는 다음 WP 준비 사항: (PENDING) — 특히 P-017(F1 수치)에 대한 판단을 요청한다.

이 문서는 구현·테스트 결과 기록이며, DONE 전환은 모든 필수 AC 충족과 GPT PASS 이후에만 한다.

### 2026-09-15 · GPT 독립 리뷰 — REVISE

- 기준: READY v1.0 `31193a3` → 구현 `7fc75ab` 및 수정 `6e9240c9f88b2f43da34c701299ed687da434ded`.
- 증거/PR head: `57988c23803b07dfa76ff373193671ff1b890f30`, PR #4. 이 판정은 위 구현자 자체 PASS/PENDING보다 우선한다. 병합/DONE 승인 없음.
- 재실행: Godot 4.7.stable 공식 headless 전체 테스트 **509 PASS / 5 FAIL, 종료1, 46.8초**. 기존 코어 회귀322건은 통과하지만 실제 scene에서 legacy 모드를 시작할 때의 회귀는 별도로 재현했다.
- reviewer 증거: [test_report](evidence/wp-003/gpt-review/2026-09-15/test_report.txt), [review_checks.gd](evidence/wp-003/gpt-review/2026-09-15/review_checks.gd), [review_checks.json](evidence/wp-003/gpt-review/2026-09-15/review_checks.json), [perf_audit.json](evidence/wp-003/gpt-review/2026-09-15/perf_audit.json).
- reviewer probe 재현: `godot --headless --path . --script res://results/evidence/wp-003/gpt-review/2026-09-15/review_checks.gd`. 게임 코드를 수정하지 않고 실제 scene 모드 전환/R 입력과 코어의 중복 콜백을 호출한다. 별도 HP 변경 진단은 원래 AC 통과 증거가 아니다.

| AC | GPT 판정 | 근거 |
|---|---|---|
| AC-01 | **FAIL** | 정상 피해/초과 미전달은 통과. 그러나 명시된 중복 붕괴 콜백을 재실행하면 collapse/recovery_created 이벤트가 각각2건, 추가 경로 재계산 발생(R-04). count 필드가1이라는 것만으로 한 번의 전환을 증명하지 못함 |
| AC-02 | **PASS** | 생존/신규 목표 전환, 좌표/HP/ID 보존, 장승 유지 경로·목표 전환 delta+1의 정상 경로를 코드와 재실행으로 확인 |
| AC-03 | **FAIL** | 정상 회수·거절·쿨다운·+5초 배치는 통과. 배치 완료 후 중복 붕괴 콜백이 같은 H1을 다시 분리하고 소비한 회수권을1로 복구하여 1회 배치 계약 위반(R-04) |
| AC-04 | **NOT RUN (필수 증거 일부)** | 수치 시험은 재실행 통과: A/B 처치0/12·핵심 피해12/0·공유사격0/1. 그러나 F3 실제 화면/독립 JSON, 개체 ID·관측 출처·target_zone·사격/처치/피해 시각 증거가 제출되지 않음. 현재 캡처는 F2만 있음(R-06) |
| AC-05 | **FAIL** | F1 기존HP120에서 LOST92.2초, 생존264, 붕괴1·핵심0 재현. F2 +5초 B배치/WON105.5초·핵심28 및 F4 패배 우선은 통과. P-017은 아래 D-032로 보완 기준 확정(R-01) |
| AC-06 | **FAIL** | 코어 초기화/종료 정지는 통과. 실제 scene의 R 재시작 후 이전 held click이 남아 새 run_id에서 재실행됨. 제출 테스트는 ID 증가만 확인하며 오래된 입력 무효화를 확인하지 않음(R-03) |
| AC-07 | **FAIL** | 제출 release의 원시 성능 수치는 통과. 그러나 scene 모드 전환 후 WP-001/002 실제 존10개 회귀(R-02), 사격 집계·구간 샘플·manifest 불일치(R-05)가 있어 전체 계약 미충족 |
| AC-08 | **FAIL** | F2의 붕괴/배치/승리 캡처와 로그는 있음. 기본 1280×340 HUD가 내곽 A/B 배치 지점·핵심 마커·유효 미리보기와 겹쳐 주요 조작 정보를 가림. d/e 캡처에서 직접 확인. F3 화면도 미제출(R-06/07) |

#### 보완 요청 (현재 구현 기준 행)

**R-01 · P1 · F1 정상 방어 승리 불성립.** `tests/test_collapse_retreat.gd:307`의 원래 F1은 재실행에서도 5건 실패했다. HP만 크게 잡아 붕괴를 막은 진단에서 전체1140체 중 처치826/외곽 도달314, 99.833초 종료였다. HP360만 적용한 별도 진단은 동일 도달314, outer46/core60, collapse0, alive0/WON. **D-032: P-017(a) 외곽 초기/최대HP360 채택**, 핵심60·피해1·웨이브·시설·존·F1 승리 조건 유지. 원래 HP120 실패를 소급 PASS로 바꾸지 않는다. 보완 구현에서 초기값·재시작 단언·UI HP/캡처를 일치시키고 F1/F2 전체 재측정한다. 자연 붕괴 시나리오와 다양한 시드 난이도는 이 단일 진단으로 보장하지 않는다.

**R-02 · P1 · legacy 모드의 실제 존을 재생성하지 않음.** `game/core/battle.gd:65,78`, `game/scenes/main.gd:229` 주변. Battle 생성 때 WP-003의10존을 만든 뒤 `_apply_mode_preset`→`reset()`은 config의 zone_set만 바꾸고 density를 재생성하지 않는다. 실제 `_apply_run_mode()`로 move/network_move를 선택한 reviewer probe에서 선언은 wp001/sandbox/immediate지만 `density.zones.size()==10`이다. 새 Config로 직접 Battle을 만드는322건 코어 시험은 이를 잡지 못한다. 초기 모드 확정 후 Battle을 만들거나 reset에서 실제 zone_set에 맞춰 density를 재생성한다. move/combat/network_move/network_combat 및 ac0*/wp002 캡처 진입을 실제 scene 경로로 시험하고 **zone ID/중심/반경이 기존8개와 동일**함을 단언한다. 로그 문자열만 확인하지 않는다.

**R-03 · P2 · 재시작이 이전 런의 입력 상태를 남김.** `game/scenes/main.gd:444`의 R 처리는 battle만 재시작하고 `_mouse_down`을 비우지 않는다. reviewer가 held click 상태에서 R을 전달하자 run_id1→2 뒤에도 `_mouse_down=true`, 다음 physics tick에 새 런의 commands_rejected가 증가했다. `_paused`도 유지되어 일시정지 중 R을 누르면 새 런이 멈춘 상태다. 재시작 시 pending/held 입력·선택 상태를 초기화하고, 지연 명령을 도입한 경로는 발행 run_id를 검사한다. 실제 R 입력을 통한 회귀로 이전 입력이 새 런에서 재시도/배치하지 않음을 확인한다. 새 런의 기본 진행 상태도 초기화한다.

**R-04 · P2 · 붕괴 처리 진입점에 중복 방어가 없음.** `game/core/battle.gd:240`. 일반 `_process_arrivals` 호출자는 count를 검사하므로 자연 피해 경로에서는1회다. 하지만 WP가 별도로 요구한 중복 붕괴 호출 시험은 없고 `_collapse()` 자체는 멱등하지 않다. 실제 피해로 붕괴→B배치 성공→같은 `_collapse` 콜백 재호출 시 H1이 다시 분리되고 right0→1, collapse/recovery_created 이벤트 각2건, path+1이 발생했다. 전환 진입점에서 이미 붕괴/종료 상태를 거절하고, 회수 대기·배치 완료·종료 후 각각 중복 호출이 상태/권리/경로/망/이벤트를 바꾸지 않는지 시험한다. 이 재현은 명시된 중복 콜백 계약 시험이며 일반 플레이에서 해당 콜백이 두 번 발생한다고 주장하는 것은 아니다.

**R-05 · P2 · 성능 증거의 집계와 출처가 계약에 맞지 않음.** `game/scenes/main.gd:333,896,974` 주변.

- combat H1 배치 시 shots33, 최종75이므로 **배치 후42발**이다. 코드가 H1 누계75에서 전체 화차 shots_total66을 빼서9로 잘못 기록했다. 같은 H1 ID의 배치 직전 누계로 차감한다. 실제 사격≥1 자체는 충족한다.
- global frame 배열은 move13173/combat14757, 구간 frames 합계는13172/14756으로 각각1개 부족하다. 마지막 `_perf.tick()`이 done으로 바뀌는 프레임은 global에 들어가고 구간 샘플에서 빠진다. 모든 global 샘플을 정확히 한 구간에 매핑하고 원시 인덱스/시각으로 검산 가능하게 한다.
- manifest.zones는8개, jangseung_anchor는 `(22,28)`로 실제 WP-003의10존·J1(44,36)/J2(22,24)와 다르다. 실제 실행 데이터에서 전체 시설/존 manifest를 생성한다.
- implementation_sha는 정확한 `6e9240c...`로 기록됐으나 필수 실행파일 SHA256과 별도 evidence_sha 연결이 없다. 실행 당시 파일 hash와 빌드 출처를 보존하고, evidence SHA는 자기참조를 피하여 별도 결과 커밋에서 연결해도 된다.

원시 검산: move **219.522FPS/p95 12.861ms**, combat **245.925FPS/p95 11.605ms**, 각60초 이상·alive 최소1000·의미 이벤트6건. 전역 수치 자체를 성능 실패라고 해석하지 않는다. 이번 리뷰에서는 신규 release 성능 실행을 하지 않았으며 제출 원시값과 기록 코드를 검산했다. 수정 후 정확한 빌드에서 양 모드10+60초를 다시 제출한다.

**R-06 · P2 · F3의 전체 상태 동일성과 화면/개체별 증거 보완.** `tests/test_collapse_retreat.gd:374,423`, `game/core/battle.gd:510`. 현재는 같은 초기 설정을 두 번 재생한 결과를 부분적인 `state_hash` 문자열로 비교한다. 이 값은 적 좌표/HP의 가중합(소수3자리), 일부 화차 상태/remaining만 포함하며 시설 좌표·센서/봉수 상태·전체 개체 ID별 상태·웨이브 누산기/타이머·망 등을 포함하지 않는다. 실제 스냅샷 복원 또는 동일한 초기/입력 재생과 완전한 구조화 상태 비교를 사용한다. A/B 각각 setup/최초 관측/공유 발사/관측 종료 JSON과 실제 렌더 캡처를 남긴다. 현재 기능 수치의 성공은 인정하나 미실행 화면·누락 상태 검증을 PASS로 대체하지 않는다.

**R-07 · P2 · 내곽 배치 영역을 HUD에서 분리.** `game/scenes/main.gd:183` HUD 크기와 `captures/wp003_f2_d_valid_inner_preview_t23.5.png`, `...e_recovery_placed_t25.5.png`. HUD가 x8~1288/y8~348을 덮어 A(1060,260)/B(900,280), 핵심(950,210)과 미리보기/HP/hover가 겹친다. 상세 디버그를 접거나 빈 공간으로 옮겨 기본 상태에서 회수 가능 구역·유효/거절 사유·연결과 핵심 HP를 동시에 읽을 수 있게 한다. HUD를 통째로 숨겨 안내까지 없어지는 방식만으로 완료하지 않는다. 수정 화면을 실제 실행에서 다시 캡처한다.

#### 기획 판단·최종 처리

- **P-017:** 외곽 유지 승리와 붕괴 후 승리를 별도 경로로 유지한다. 합격 조건을 붕괴 후 승리로 완화하는 안(d)은 채택하지 않는다. 최소 변경안(a) HP360을 D-032로 채택하고 재측정한다. HP 조정은 외곽 방어 여유만 주며, 화력/센서/웨이브/새 존을 동시에 바꾸지 않는다.
- **P-018:** 실제 실패를 종료1로 보고한 처리는 적절하다. 성공 코드 강제·F1 제외·verify 우회로 해결하지 않는다. 보완 후 모든 필수 테스트 종료0을 요구한다.
- 기존 D-019~027의 존·회수 대상·분리 중 쿨다운·HP 버퍼·5초 배치 기준은 유지한다. D-032의 HP 변경만 후속 보완 기준이다.
- 최종 **REVISE**. 기능의 큰 흐름과 F2/F3 수치는 성립하나 회귀·중복 호출·입력 초기화·필수 증거·가독성을 보완해야 한다. 위 수정을 적용한 구현 SHA와 새 결과로 재리뷰한다.

## 보완 회차 · 2026-09-15 · GPT 1차 리뷰(REVISE `f379bea`) R-01~07 반영 — 재리뷰 PENDING

- 기준: GPT 리뷰 커밋 `f379bea`(D-032 외곽 HP 360, R-01~07) · 보완 구현 커밋 **`8ec66aa`**(R-01~07) → `2ed2e02`(헤드리스 커서) → **`41ff91c`**(마지막 측정 프레임 구간 포함; 검증한 게임 트리) → `c1ff134`(uid) · 스크립트 `0406922`/`c5f9347`/`649f328`/`a89d538` · 결과·증거 커밋: 이 문서의 커밋(별도 문서 커밋으로 자기참조 회피)
- 원칙: HP 이외의 수치(핵심 60·피해 1·웨이브·시설·존·F3 합격선)는 그대로다. D-032가 대체한 것은 외곽 HP 120→360 하나뿐이며, 이전 회차의 HP 120 결과(F1 FAIL)는 위 절에 보존한다.
- 자동 검증: `godot --headless --path . --script res://tests/run_tests.gd` → **780 passed / 0 failed (47.7 s; WP-001/002 회귀 322 + WP-003 코어 + scene 진입 경로)**, 종료 코드 **0**(P-018 해소: F1이 실제로 통과하므로). 신규 스위트 `tests/test_scene_modes.gd`(실제 scene 진입 경로) 포함. 리포트: `wp-003/tests/test_report.txt`.
- 일괄: `.\scripts\verify.ps1 -Wp003`(테스트 → F1 타임라인 → F3 A/B 장부 → F2/F3 캡처 → 릴리스 export → collapse 성능 2종, 각 단계 계약 검사)가 종료 코드 0으로 끝났다. 승인된 WP-001/002 증거 파일은 건드리지 않았다.

### R-항목별 조치

| R | 조치 (파일) | 검증·증거 |
|---|---|---|
| **R-01** F1 불성립 → D-032 | `config.gd` `outer_hp` 360, `run_state.gd` 기본값, 테스트 단언(setup·F4 복원·doorstep 359)·HUD/캡처 자동 반영 | **F1 WON 99.8 s, 붕괴 0, 외곽 HP 46/360, 핵심 60, 처치 826 / 도달 314, 생성 1140=처치+도달+생존** — GPT 진단(99.833 s / 46 / 314)과 일치. `tests/f1_timeline.json`. F2 재실행: 붕괴 tick 1200, +5 s B 배치, WON 105.5 s 핵심 28(변화 없음: 20 s 강제 HP 1은 초기값과 무관) |
| **R-02** legacy 모드 존 재생성 | `battle.gd` `reset()`이 `config.zone_set`으로 DensityDetector 재생성(`zone_set` 필드, `zone_state()`); D-033 | `tests/test_scene_modes.gd`: 실제 `_apply_run_mode()`로 `--perf move/combat/network_move/network_combat`·`--capture ac01/ac02/ac06/wp002_a` 진입 → live DensityDetector 8존, **Z0~Z7 id/이름/중심/반경이 WP-001 표와 동일**, sandbox/immediate/구역 규칙 off/웨이브 off/목표 (47,10)/fixture·시설 수 확인. WP-003 시나리오(collapse_*, f2, f3a/b)는 10존·waves 확인. 리뷰어 프로브 `review_checks.gd`를 이 빌드에서 재실행하면 `actual_zones` 8 (아래) |
| **R-03** 재시작 입력 잔존 | `main.gd` `_reset_input_state()`(홀드 클릭+발행 run_id·일시정지·잔상·알림·오버라이드 초기화), 홀드 재시도는 발행 run_id==현재 run_id일 때만; 스크립트 `reset`도 동일; D-035 | `test_scene_modes.gd` "R-03": 홀드+일시정지 상태에서 실제 `KEY_R` → run_id+1, `_mouse_down` false, `_paused` false, 다음 physics tick에 명령 0건·틱 진행; 오래된 run_id 홀드는 명령 없이 폐기; 현재 런 홀드는 계속 재시도(기존 동작) |
| **R-04** 붕괴 멱등 | `battle.gd` `_collapse()` 진입 시 `collapse_count>0`/INNER_ONLY/종료면 false·무변경(`RunState.collapse_calls_ignored`만 증가, 이벤트 없음); 공개 `collapse()`; D-034 | 테스트 "R-04": 실제 도달 붕괴 후 (a) 대기, (b) B 배치 후, (c) LOST 후 각각 중복 호출 → false, **`full_state_json()` 동일**, 권리 1/0/0 유지, H1 재분리 없음, collapse/recovery_created 이벤트 각 1, path_version·topology_version 불변; 재시작이 카운터 초기화 |
| **R-05** 성능 집계·출처 | `main.gd`: H1 배치 시점 누계 기록(`h1_shots_at_placement`) 후 H1 자신의 델타; 마지막 측정 프레임도 구간에 포함(`segments_cover_all_frames`, 구간별 `frame_index_start/end`·`t_measure_start/end`); manifest를 live 데이터로 생성(`zones` 10, `structures_at_start/end`, `scripted_commands`, `fixture`); 실행파일 `executable{basename, sha256, size_bytes}` 자체 기록 + `perf_with_memory.ps1`이 Get-FileHash로 독립 계산·대조(불일치 시 실패); `verify.*` 6c에 검사 추가; D-038 | 회차 4 JSON(아래 표): `segments_frames_total == frames`, H1 배치 후 42발(배치 시 33 → 최종 75), manifest 존 10·시설 18·J1 (44,36)/J2 (22,24)·회수 B (44,13), exe SHA-256 `56ce8e8c3cbabf138b3c96fad462e6afe5fddd801808b2c9716c23461c6810ce`(게임 자체 기록 = 외부 계산, `.memory.json`) |
| **R-06** F3 전체 상태·개체별 증거·화면 | `battle.gd` `full_state()/full_state_json()`(D-036: 모든 적 id·좌표·HP·속도·오프셋, 모든 시설·대기, 망 간선·센서별 관측 id·화차별 인지 id, 경로, 존, 런(run_id 제외), 웨이브 누산기, RNG, 카운터); F3 테스트가 A/B 사전 상태를 **완전 상태 문자열로 비교**, F4 종료 불변·재시작 재현성도 동일; `game/tools/f3_tracker.gd` + `wp003_f3_evidence.gd` → `tests/f3_ab.json`; `--capture=wp003_f3a|wp003_f3b` | `f3_ab.json`: `state_identical_before_placement: true`(sha256 `1f3010ab077ba28b…`), A/B 각각 setup(배치 직후 full_state)·최초 관측(개체 12 id별 S4 관측/H1 인지/출처, H1 인지 존 카운트 Z9=12(B)/0(A))·첫 H1 볼리(B: tick 349, Z9, 로컬 0/공유 12, 처치 0 → tick 398 Z7 로컬 12 처치 12; A: 없음)·종료(개체별 운명: B 12 처치(tick 398, 첫 인지 출처 shared, tick 301) / A 12 핵심 도달(tick 522)). 요약 **B 공유전용 1 / 처치 B−A 12 / 핵심 피해 A−B 12**. 캡처 A 4장·B 5장(`wp003_f3a_*`, `wp003_f3b_*` + 로그 JSON에 3개 시점 full_state) |
| **R-07** HUD 분리 | `main.gd`: 좌상단 패널(≤816 px, 광장·경복궁 밖)에 런/방어 상태·HP·회수 안내·조작, 좌하단 패널(y≥600, x<880)에 상세(경로·밀도·화차·봉수망·인지, `D`로 접기)와 알림; `overlay_layer.gd` 핵심 HP 바·라벨을 마커 위로; 복원 화차의 이전 표적 진단 초기화(`placement.gd` restore); D-037 | 재캡처 `wp003_f2_d/e`: 내곽 전체·핵심 마커·B (44,13) 미리보기/배치·hover 패널이 HUD와 겹치지 않음. F3 캡처도 동일 레이아웃 |

### 리뷰어 프로브 재실행 (`results/evidence/wp-003/gpt-review/2026-09-15/review_checks.gd`, 보완 빌드)

`results/evidence/wp-003/followup/review_checks_rerun_8ec66aa.json` (리뷰어 스크립트를 그대로 실행, 출력만 별도 파일에 보관 — 리뷰어 디렉터리는 손대지 않음):

| 프로브 | 1차 리뷰(6e9240c) | 보완 빌드 |
|---|---|---|
| `legacy_mode_repro` move / network_move `actual_zones` | 10 / 10 | **8 / 8** (declared wp001, sandbox, immediate) |
| `restart_input` held_click / paused / old_hold_dispatched | true / true / true | **false / false / false** (run_id 1→2) |
| `duplicate_collapse_callback` collapse_events / recovery_created_events / detached_again / right / path_delta | 2 / 2 / true / 1 / 1 | **1 / 1 / false / 0 / 0** |
| `f1_hp360_proposal_diagnostic_only` | WON 99.833 s, 외곽 46, 도달 314 | 동일(이제 기본값) |

### 성능 회차 4 (보완 빌드 `41ff91c`; manifest `implementation_sha` 41ff91c, `-dirty` 없음)

환경은 위와 동일(Godot 4.7.stable 릴리스 export, gl_compatibility, 1920×1080, vsync off, Ryzen 5 7600 / RTX 4070 SUPER / 63 GB). 시나리오·설정은 D-027 그대로(fixture C 18시설·10존·`benchmark_hold_alive`·외곽 HP 1e6→측정 20 s에 1·25 s B 배치·핵심 무적 집계). 실행 파일 SHA-256 `56ce8e8c3cbabf138b3c96fad462e6afe5fddd801808b2c9716c23461c6810ce`(게임 자체 기록과 외부 Get-FileHash 일치, 기준 SHA `41ff91c`).

| 시나리오 | 프레임 / 초 | 생존 min / avg / max | 부하 유지 | 평균 FPS | 프레임 ms p50 / **p95** / p99 / max | sim step ms avg / p95 | 구간 [0,20) / [20,25) / [25,60] avg FPS · p95 · 프레임 수 (원시 인덱스) | 구간 합 = 전체 | 이벤트·전환 | 워킹셋 MB 시작→종료 |
|---|---|---|---|---|---|---|---|---|---|---|
| collapse_move | 13,294 / 60.00 | **1000 / 1000.0 / 1001** | true | **221.5** | 2.67 / **12.72** / 16.13 / 34.01 | 3.79 / 7.37 | 167.7·15.62·3,354 (0–3353) / 270.7·11.55·1,354 (3354–4707) / 245.3·12.19·8,586 (4708–13293) | **13,294 = 13,294** | 6건 tick 1806(trigger·collapse·recovery_created·outer_deactivated·target_changed) + recovery_placed 2106; 트리거→붕괴 0틱, 붕괴→배치 300틱, 배치 ok(1회), pv 4→5, 위상 v16→v18, 핵심 흡수 2,073(무적), 후보 평가 9,305 | 179.8→183.2 |
| collapse_combat | 14,838 / 60.01 | **1000 / 1000.0 / 1001** | true | **247.3** | 2.54 / **11.72** / 13.97 / 19.32 | 2.42 / 4.49 | 207.4·13.28·4,145 (0–4144) / 273.8·11.26·1,372 (4145–5516) / 266.2·11.21·9,321 (5517–14837) | **14,838 = 14,838** | 6건 tick 1805 + recovery_placed 2106; 트리거→붕괴 0틱, 붕괴→배치 301틱, 배치 ok(1회), pv 4→5, 위상 v16→v18; 구간 발사 138(공유전용 44: 붕괴 전 43·대기 1·배치 후 0), **H1 배치 후 42발 / 954처치**(배치 시 33 → 최종 75), 핵심 흡수 5 | 173.2→181.6 |

- 예산: 평균 ≥60 FPS·p95 ≤25 ms·전 프레임 alive ≥1000 → 두 시나리오 모두 충족. D-027 6 이벤트 각 1건(`recovery_refused` 0), 트리거→붕괴 0틱, 배치 1회 성공, 경로 버전 기대+1.
- R-05 검산: 각 시나리오 `frame_us_raw` 길이 = 구간 `frames` 합 = `global_frames`; 구간 `frame_index_start/end`로 원시 배열을 잘라 재계산 가능. combat의 H1 배치 후 사격 42발은 `h1_shots_at_placement`(33) 대비 `h1_final.shots`(75)의 델타이며 스냅샷 `after_placement_25s.hwacha_brief`의 H1 shots와 같다.
- 이전 회차(1 무효·2·3)는 `*_run1_hold_off`, `*_run2_pre_codex`, `*_run3_6e9240c` 파일로 보존한다.

### 보완 후 AC 자체 판정 (GPT 재리뷰 대상)

| AC | 보완 후 | 근거 |
|---|---|---|
| AC-01 | PASS(자체) | 실제 피해 붕괴 1회 + R-04 중복 콜백 3상태 무변경(full_state 동일) |
| AC-02 | PASS(자체) | 변경 없음(GPT PASS), 회귀 통과 |
| AC-03 | PASS(자체) | 배치 완료 후 중복 콜백이 H1을 재분리하지 않고 권리 0 유지(R-04) |
| AC-04 | PASS(자체) | F3 완전 상태 동일성 + 개체별 장부 JSON + A/B 실제 화면(R-06) |
| AC-05 | PASS(자체) | F1 WON(HP 360, D-032) / F2 WON / F4 LOST 우선; 스위트 종료 0 |
| AC-06 | PASS(자체) | 실제 R 입력 후 홀드·일시정지 초기화, 오래된 run_id 입력 폐기(R-03) + 코어 재시작 완전 상태 재현 |
| AC-07 | PASS(자체) | 실제 scene 경로 8존 회귀(R-02), 회차 4 성능·집계·manifest·exe 해시(R-05), 회귀 780 passed / 0 failed (47.7 s; WP-001/002 회귀 322 + WP-003 코어 + scene 진입 경로) |
| AC-08 | PASS(자체) | HUD 분리 재캡처(R-07), F3 화면 제출(R-06) |

### GPT 재리뷰

- 검토일 / 검토한 구현 커밋: 2026-09-15 / `41ff91c` (보완 구현 `8ec66aa` → `2ed2e02` → `41ff91c`; 리뷰 대상 diff `f379bea..1598d23`)
- 최종 판정: **PASS 8 / FAIL 0 / NOT RUN 0** (`f5d7e69`, 아래 절). 이에 따라 WP-003을 **DONE**으로 전환한다(2026-09-15).

### 2026-09-15 · GPT 재리뷰 2차 — PASS

- 검토 기준: 1차 REVISE `f379bea`와 D-032 외곽HP360. 보완 diff `f379bea..1598d23ff48348394088b439b581b76ed117ac9e` (PR #4).
- 검증한 게임 구현: `41ff91c` (보완 `8ec66aa` → `2ed2e02` → `41ff91c`). 이후 `c1ff134`의 uid 추가를 제외하면 증거 head `1598d23`까지 게임 소스 변경 없음. 이번 리뷰는 게임 코드를 수정하지 않았다.
- 최종 판정: **PASS — AC-01~08 모두 충족, R-01~07 해소.** 과거 HP120 실패/1차 REVISE는 이력으로 보존한다. PR 병합은 수행하지 않는다.

| AC | GPT 판정 | 독립 확인 결과 |
|---|---|---|
| AC-01 | **PASS** | 실제 도달 피해·초과 미전달 회귀 통과. 중복 붕괴가 대기/배치/종료 상태에서 거절된다. 기존 reviewer 재현에서도 collapse/recovery_created 각1, 경로 추가 변화0 |
| AC-02 | **PASS** | 생존/신규 목표 전환·ID/HP/좌표 보존·장승 유지 경로 회귀 통과. 이전 PASS 유지 |
| AC-03 | **PASS** | 정상 회수/거절·분리 쿨다운·+5초 배치 통과. 배치 후 중복 콜백에도 H1 재분리 없음, 회수권0 유지 |
| AC-04 | **PASS** | F3 도구 독립 재실행: A/B 사전 구조화 상태 동일, 처치0/12·핵심 피해12/0·공유전용0/1. 개체12개별 관측·사격·운명 JSON 및 A/B 실제 렌더 캡처 확인 |
| AC-05 | **PASS** | D-032 기본HP360 F1: WON99.833초, 외곽46/핵심60/붕괴0/생존0/생성1140. F2: +5초 B배치/WON105.5초/핵심28. F4 패배 우선 통과 |
| AC-06 | **PASS** | 종료120틱·구조화 상태/재시작 회귀 통과. 실제 R 입력과 기존 reviewer 재현에서 held=false/paused=false/이전 입력 재실행=false. 오래된 run_id 홀드 폐기 시험 포함 |
| AC-07 | **PASS** | 전체 테스트780/0(기존 코어322 포함), 실제 scene 경로의8존 회귀 통과. 제출 release 양 모드의 원시 배열·구간·6이벤트·18시설/10존·H1 델타·실행파일 해시 일치 확인 |
| AC-08 | **PASS** | F2 유효 미리보기/배치 후 화면에서 기본 HUD가 내곽·핵심·B를 가리지 않음. F3 B 첫 공유사격, A/B 종료 화면의 처치·핵심HP가 JSON과 일치. README/verify의 재현 절차 확인 |

#### 재실행·검산 증거

- `godot --headless --path . --script res://tests/run_tests.gd -- --report=<absolute-output>`: **780 PASS / 0 FAIL, 48.1초, 종료0**. [재리뷰 test_report](evidence/wp-003/gpt-review/2026-09-15-followup/test_report.txt).
- 기존 reviewer probe는 출력 위치만 새 회차 폴더로 변경해 실행했다. [스크립트](evidence/wp-003/gpt-review/2026-09-15-followup/review_checks.gd), [결과](evidence/wp-003/gpt-review/2026-09-15-followup/review_checks.json). move/network_move 실제 존8/8, 재시작 잔존입력 없음, 중복 붕괴 이후 권리0·이벤트1·경로delta0·재분리false를 확인했다.
- `godot --headless --path . --script res://game/tools/wp003_f3_evidence.gd -- --out=<absolute-output>`: 종료0. 출력 SHA256 **277de479b74fd09df26e98babba03c14fc20c1b1589076f4c9c91a5ec5c98cea**, 제출 `tests/f3_ab.json`과 바이트 동일하여 JSON은 중복 저장하지 않았다. B 첫 공유 볼리는 Z9, 이후 Z7에서12체 처치. A는12체 핵심 도달, 피해12. 이 F3 한정 운명 분류는 마지막 위치의 핵심 거리와 처치/도달 집계·사격 로그가 일치함을 확인했으며, 다른 미래 fixture의 일반 이벤트 추적기로 검증한 것은 아니다.
- [성능 검산 JSON](evidence/wp-003/gpt-review/2026-09-15-followup/perf_audit.json): move **13,294프레임 / 60.004939초 / 221.548FPS / p95 12.720ms**, combat **14,838프레임 / 60.008629초 / 247.264FPS / p95 11.716ms**. 모든 frame_us>0, 원시 배열 길이=frames, 모든 alive≥1000.
- 구간 인덱스가0부터 마지막 프레임까지 겹침/누락 없이 연속이며 각 구간 frames/FPS/p95를 원시 배열로 재계산해 일치를 확인했다. 세 구간 후보 평가 모두>0. 의미 이벤트 각1건·실제 도달 붕괴·배치 성공1회·path4→5. combat H1 델타 **75−33=42발**로 일치한다.
- manifest 실제10존·18시설과 외부 메모리 리포트의 실행파일 SHA256 **56ce8e8c3cbabf138b3c96fad462e6afe5fddd801808b2c9716c23461c6810ce** 일치, 두 실행 종료0. 구현 SHA `41ff91c`, 증거 SHA `1598d23`으로 연결한다. 이번 재리뷰에서 release 성능 실행 자체를 다시 하지 않았으며 제출 원시 증거와 기록 코드를 검산했다.

#### 기획 판단

D-032의 HP360은 정상 외곽 방어와 붕괴 후 재편 승리를 함께 성립시키는 프로토타입 초기값으로 유지한다. F3 합격선을 변경하지 않았고 연결 효과를 개체별 증거로 확인했다. 중복 거절 진단 카운터의 증가는 게임 상태·권리·이벤트 변경과 구분하여 허용한다. R-01~07에 대한 추가 필수 수정 요청은 없다. 다중 시드 난이도·완성형 재화·최종 시각 품질은 이번 PASS 범위가 아니다.
