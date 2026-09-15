# WP-003 Result

- 작성일: 2026-09-15
- WP / 상태: WP-003 검증·붕괴·후퇴·재편 / **REVIEW** (GPT 판정 PENDING). **AC-05의 F1(정상 방어 승리)은 계약 수치로 FAIL** — 아래 분석과 P-017 제안 참조.
- 기준 커밋: `31193a3` ("docs(wp-003): finalize fixtures and acceptance criteria, mark READY", main)
- 검증한 구현 커밋: `7fc75ab` ("feat(wp-003): …") → **Codex 리뷰 반영 `6e9240c`** ("fix(wp-003): scripted scenarios reapply every mode key; held click follows run mode; quit-after on run end; no stale goal marker"). 게임 코어(`game/core/`)는 두 커밋에서 동일하며 변경은 `game/scenes/`뿐이다.
- 브랜치: `wp/003-collapse-retreat` · PR: https://github.com/darkrunar/hanyang-defense/pull/4 (Ready for review, 병합 금지)
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
