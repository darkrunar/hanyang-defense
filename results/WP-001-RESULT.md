# WP-001 Result

- 작성일: 2026-09-13
- WP / 상태: WP-001 Enemy Flow Prototype / **REVIEW** (1차 GPT 판정 **REVISE** → 2026-09-13 보완 재리뷰 **PASS**. 아래 "보완 회차" 및 GPT Review 참조)
- 기준 커밋: `17d17e9c685bcfd9a1007f7c36aca0daeaf572db` (origin/main, "docs: add concept art and gameplay mockup references")
- 검증한 구현 커밋: 1차 `7af1f9288a26bcf8f43fdb091f8de1f2be83b4b1` ("feat(wp-001): …") → **보완 회차 `0f3a8328eb722bb51fdc2c8a55664175448bb5e8`** ("fix(wp-001): occupancy follows movement (R-01) and perf holds the 1000-enemy load (R-02)")
- 브랜치: `wp/001-enemy-flow` · Draft PR: https://github.com/darkrunar/hanyang-defense/pull/1
- 실행 환경 / 엔진·버전: Godot 4.7.stable.official.5b4e0cb0f (GDScript, 2D, gl_compatibility / OpenGL 3.3) · Windows 11 Home 10.0.26200 · AMD Ryzen 5 7600 (6C/12T) · NVIDIA GeForce RTX 4070 SUPER (driver 591.86) · 63.2 GB RAM · 1920×1080

이 문서는 결과 양식(`results/RESULT_TEMPLATE.md`)을 기준으로 작성했다. 모든 수치는 `results/evidence/` 아래의 원시 파일에서 가져왔으며, 이 문서를 담는 커밋은 구현 커밋과 분리한다 (CLAUDE.md 자기참조 규칙).

## 구현 결과

엔진·화면·성능 예산 결정은 [DECISIONS D-007~D-011](../docs/DECISIONS.md)에 기록했다. Unity는 설치되어 있었으나 채택하지 않았다 (UnityMCP 연결 실패, batchmode 반복 비용, 빌드 모듈·라이선스 미검증). SYSTEM_SPEC의 잠정 성능 예산은 낮추지 않고 그대로 채택했다 (D-009).

### 변경 파일과 각 변경 목적

| 파일 | 목적 |
|---|---|
| `project.godot`, `export_presets.cfg` | Godot 4.7 프로젝트 정의 (1920×1080, canvas_items stretch, vsync off, gl_compatibility), Windows x86_64 릴리스 export 프리셋 |
| `game/core/terrain_grid.gd` | 96×54 셀(20px) 정적 지형 + 시설 점유 레이어. 통행 가능 판정의 단일 출처 |
| `game/core/path_network.gd` | PathNetwork: 목표에서 8방향 Dijkstra(모서리 끼기 금지) 거리장·흐름장, `path_version`, 거리장을 건드리지 않는 도달성 프로브 |
| `game/core/enemy_sim.gd` | EnemySpawner + 이동: SoA 풀, 세 진입로 라운드로빈 생성, 흐름장 조향, **생성 누계/동시 생존/처치/누수 분리 집계**, 폭발 피해 1회 적용 |
| `game/core/density_detector.gd` | DensityDetector: 원형 후보 영역, 경계 포함(`<=`), 생존 적만 집계 |
| `game/core/placement.gd` | Barricade/Placement: 2×2 footprint, 경계·지형·중복·적 점유·전체 경로 차단 거절, 거절 시 상태 불변. 장승만 통행 차단(D-011) |
| `game/core/hwacha.gd` | Hwacha: 사거리 내 최고 밀도 영역, 동률 시 낮은 zone id, 빈 표적이면 미발사(재장전 소모 없음), 볼리당 피해·사망 1회 |
| `game/core/battle.gd` | 고정 스텝 오케스트레이터, 명령(설치/제거/초기화), 관측 스냅샷 |
| `game/core/config.gd` | 시드·동시 생존 목표·밸런스 값 전부. `--set key=value`, `--config=file.json` |
| `game/maps/hanyang_test_map.gd` | 세 진입로(남대문·서대문·동대문) + 공통 목표(핵심 시설) 회색상자 맵, 8개 밀도 존, 초기 화차 4대, AC 시나리오 앵커 |
| `game/scenes/main.tscn`, `main.gd` | MultiMesh 적 렌더링, 조작, HUD, `--capture` / `--perf` 스크립트 모드 |
| `game/scenes/terrain_layer.gd`, `overlay_layer.gd` | 지형 정적 드로우 / 존·시설·사격·커서 오버레이 |
| `game/tools/perf_recorder.gd` | 벽시계 프레임 간격·p50/p95/p99·sim step 비용·초당 샘플 JSON 기록 |
| `game/tools/dump_map.gd`, `probe_occupancy.gd` | ASCII 지형·도달성 덤프, 포화 상태 설치 성공률 측정 도구 |
| `tests/run_tests.gd`, `test_framework.gd`, `test_*.gd` | 헤드리스 검증 116건 (AC-01~06 + 결정성) |
| `scripts/verify.ps1`, `verify.sh`, `perf_with_memory.ps1` | 새 체크아웃 재현 절차 일괄 실행. 릴리스 템플릿은 메모리 카운터가 0이므로 외부 프로세스 워킹셋 샘플러 포함 |
| `docs/DECISIONS.md` | D-007 엔진, D-008 화면·렌더러, D-009 성능 예산·기준 장비, D-010 공개 저장소(D-004 대체), D-011 화차 비차단; 제안 P-007~P-009 |
| `README.md`, `CLAUDE.md`, `docs/ROADMAP.md`, `backlog/WP-001.md` | 현재 상태·공개 범위·설치/실행/테스트/빌드 절차, 실행 환경 계약, WP-001 → REVIEW |
| `.gitignore`, `.gitattributes` | `.godot/`, `build_out/` 제외; 엔진 파일 줄끝·바이너리 지정 |

## 실행·재현 절차

필요 도구: Godot 4.7.stable 표준 에디터(`godot`으로 PATH 등록), 같은 버전의 Windows export template(빌드·성능 측정에만), Git. 추가 패키지 없음. 상세는 README "실행 환경".

```bash
git clone https://github.com/darkrunar/hanyang-defense.git && cd hanyang-defense && git checkout wp/001-enemy-flow
```

| 단계 | 명령 | 산출물 |
|---|---|---|
| 자동 검증 | `godot --headless --path . --script res://tests/run_tests.gd -- --report=<abs>/results/evidence/test_report.txt` | 종료 코드 0, `test_report.txt` |
| 지형 덤프 | `godot --headless --path . --script res://game/tools/dump_map.gd` | ASCII 맵, 경로별 도달성, 화차 커버리지 |
| 화면 캡처 | `godot --path . --rendering-driver opengl3 -- --capture=ac01|ac02|ac06 --out-dir=<abs>/results/evidence/captures` | PNG + 상태 JSON 로그 |
| 릴리스 빌드 | `godot --headless --path . --export-release "Windows Desktop Release" build_out/windows/hanyang_defense_wp001.exe` | 109 MB 단일 exe (pck 내장) |
| 성능 측정 | `.\scripts\perf_with_memory.ps1 -Scenario move|combat -Out results\evidence\perf\perf_<sc>_1000_release.json` | 프레임 JSON + `.memory.json` |
| 일괄 | `.\scripts\verify.ps1` / `scripts/verify.sh` (`--quick`: 빌드·성능 제외) | 위 전부 |
| 플레이 | `godot --path . --rendering-driver opengl3` | 조작: LMB 설치(홀드 재시도) · RMB 제거 · 1/2 장승/화차 · C 전투 · Z 밀도 · G 사거리 · P 정지 · R 초기화 · H HUD · F12 캡처 |

시드·설정: 기본 시드 `20260913`, `target_alive=1000`, `spawn_rate=420/s`, 적 HP 60 · 속도 58px/s(±22%), 화차 사거리 200 · 폭발 반경 55 · 피해 34 · 재장전 0.8s, 고정 스텝 60 Hz. 모두 `game/core/config.gd`. 캡처 모드는 시뮬레이션을 6배속(프레임당 6스텝)으로 진행하며, 결과는 고정 스텝이므로 배속과 무관하게 결정적이다 (결정성 테스트로 확인).

## Acceptance Criteria

| AC | PASS / FAIL / NOT RUN | 기대 결과 | 실제 결과 | 증거 파일·로그·화면 |
|---|---|---|---|---|
| AC-01 | **PASS** | 처치 비활성 상태에서 동시 생존 ≥1,000, 세 진입로 모두 사용, 생성 누계와 구분 | t=30s: 동시 생존 **1000** (최고 1000), 생성 누계 2061, 누수 1061, 처치 0. 경로별 생존 남대문 297 / 서대문 352 / 동대문 351 (경로별 생성 각 687). 남대문 두 골목 모두 사용(Z0 13, Z1 9) | `captures/ac01_t30_1000_alive_three_routes.png`, `captures/ac01_log.json`, `test_report.txt` "AC-01" 2건(장부 일치 spawned = alive+killed+leaked 6회 검사 포함) |
| AC-02 | **PASS** | 유효한 장승 설치 후 우회, 제거 후 통행 복원 (동일 시드) | 같은 시드 t=30s: 기준 Z0 13 / Z1 9 → 서편 골목 장승(앵커 44,36) 설치 시 **Z0 0 / Z1 22**, path_version 2→4, 남대문 목표 도달 계속(387). t=30s 제거 → path_version 5, t=42s **Z0 19 / Z1 20** 로 복원. 헤드리스: 차단 셀 도달 불가·경로 유지·제거 후 도달 가능 확인 | `captures/ac02_a_reference_t30.png`, `ac02_b_west_lane_blocked_t30.png`, `ac02_c_restored_t42.png`, `ac02_log.json`; `test_report.txt` "AC-02 jangseung reroutes…" 15건 |
| AC-03 | **PASS** | 전체 경로 차단·점유 위치 배치 거절, 상태 손상 없음 | 서문 북편 골목 차단 후 남편 골목 차단 시도 → `WOULD_BLOCK_ALL_PATHS` 거절, path_version·시설 수·dist·flow 배열 **byte-identical**, footprint 셀 비어 있음, 서대문 경로 계속 도달(생존 351·도달 335). 점유 셀 → `ENEMY_OCCUPIES_CELL`(셀 번호 보고), 점유 해소 후 동일 배치 수락. 지형 `TERRAIN_BLOCKED`, 경계 `OUT_OF_BOUNDS`, 중복 `STRUCTURE_OVERLAP`. 포화 골목 스윕: 720회 중 82회 수락(11.4%), 나머지 전부 점유 거절, 다른 사유 0 | `test_report.txt` "AC-03" 4개 케이스 34건; `game/tools/probe_occupancy.gd` (10초 스윕 2400회 중 87회, 3.63%) |
| AC-04 | **PASS** | 알려진 좌표 밀도: 반경 경계 포함, 사망 제외 | 중심(900,750) r=45: 내부 3 + 경계 정확히 2 + 외부 3(+0.5px 포함) → **5**; 일괄 evaluate 동일. 6개체 → 치명 볼리 후 밀도 0, killed_total 6, alive 0 | `test_report.txt` "AC-04" 2개 케이스 8건 |
| AC-05 | **PASS** | 사거리 내 최고 밀도 선택, 동률·빈 표적·사망 중복 처리 | 사거리 밖 400 무시하고 in-range 9 선택; 사거리 경계(=200) 포함, 199.9 제외. 동률 [7,7,7]→Z0, [2,7,7]→Z1, 반복 안정. 빈 필드 5초 0발·재장전 0 유지, 표적 등장 즉시 다음 스텝 발사. 폭발: 경계(=55) 피해 1회(60→35→10), 56px 밖 무피해, 3발째 5처치·killed_total 5, 사체 재사격 0. 1s 재장전 5초 → 5발 | `test_report.txt` "AC-05" 5개 케이스 30건 |
| AC-06 | **PASS** | 배치 변경으로 사격 구역 내 적 수 증가 (같은 시드·시각 전후 비교 + 캡처) | 헤드리스, 같은 시드, 창 [30s,50s]: 동편 골목 평균 밀도 **24.8 → 44.1**, 화차·중영 처치 **231 → 863**, 남대문 도달 2 → 0, 차단 골목 0. 캡처 t=35s: 화차·중영 **같은 38발**로 처치 413 → 1299, 표적 Z0(27)→Z1(55), 전체 처치 3161→3811, 누수 5→0 | `captures/ac06_a_before_t35.png`, `ac06_b_after_t35.png`, `ac06_log.json`; `test_report.txt` "AC-06" 4건 |
| AC-07 | **PASS** | D-009 예산: 1080p 릴리스, 동시 1,000, 10s 준비 + 60s 측정, 평균 ≥60 FPS, p95 ≤25ms, 이동 전용 / 경로 변경·전투 각각 | **move** 평균 444.8 FPS, p95 6.77ms, p99 8.63ms, 생존 평균 999(최소 993) · **combat(+12회 경로 재계산)** 평균 461.5 FPS, p95 6.31ms, p99 7.71ms, 생존 평균 994(최소 931). 워킹셋 ≈168→172 MB. 아래 "성능" 절 | `perf/perf_move_1000_release.json`, `perf_combat_1000_release.json`, `*.memory.json` |
| AC-08 | **PASS** | 새 체크아웃에서 실행·검증 재현 가능, 엔진·버전·명령·설정·시드·제한 기록 | README "실행 환경", `scripts/verify.*`, 이 문서 "실행·재현 절차". 이번 세션에서 빈 폴더 → clone → 위 절차로 전 증거 생성. 제한: Windows 전용 export 프리셋, 시스템 폰트 폴백(한글), Parsec 가상 디스플레이 존재 | 이 문서, README, `scripts/` |

자동 검증 합계: **116 passed / 0 failed** (21.7 s, `results/evidence/test_report.txt`). 결정성: 같은 시드·입력의 두 실행이 생존·처치·누수·존 밀도·위치 해시까지 일치, 다른 시드는 불일치.

## 성능

- OS / CPU / GPU / RAM / 해상도 / 빌드 설정: Windows 11 Home 10.0.26200 / AMD Ryzen 5 7600 6-Core (12 threads) / NVIDIA GeForce RTX 4070 SUPER, OpenGL 3.3.0 NVIDIA 591.86 / 63.2 GB / 창 1920×1080 (screen 1920×1080), vsync **disabled**(mode 0) / `exported release`, x86_64, pck 내장, gl_compatibility.
- 주의: 이 장비에는 Parsec 가상 디스플레이 어댑터가 함께 설치되어 있다. vsync를 끄고 벽시계 프레임 간격으로 순수 비용을 측정했으므로 프레젠테이션 경로의 영향은 배제했지만, 일반 단일 모니터 환경과 완전히 같다고 보장하지는 않는다.
- 시나리오 / 동시 생존 적 수 / 준비·측정 시간:

| 시나리오 | 내용 | 측정 프레임 | 생존 avg / min / max | 평균 FPS | 프레임 ms avg / p50 / **p95** / p99 / max | sim step ms avg / p95 / max |
|---|---|---|---|---|---|---|
| move | 전투 비활성, 이동·생성·밀도만 | 26,688 / 60.00 s | 999.1 / 993 / 1000 | **444.8** | 2.25 / 1.42 / **6.77** / 8.63 / 40.26 | 1.07 / 1.38 / 2.98 |
| combat | 전투 활성 + 10초 주기 장승 제거→1.5초 후 재설치 (경로 재계산 12회, 거절 0회, path_version 14), 화차 310발, 처치 8,106 | 27,693 / 60.00 s | 993.5 / 931 / 1000 | **461.5** | 2.17 / 1.40 / **6.31** / 7.71 / 13.65 | 2.24 / 6.79 / 7.86 |

- 평균 FPS / p95 프레임 시간 / 메모리: 위 표. 메모리(외부 `Get-Process` 1 Hz 샘플, 릴리스 템플릿은 내부 정적 메모리 카운터가 0): move 워킹셋 측정 시작 167.7 → 종료 171.1 MB (최대 171.1, private 최대 236.9 MB) · combat 169.9 → 171.6 MB (최대 171.6, private 최대 234.3 MB). 60초 동안 증가 ≤3.4 MB로 누수 징후 없음.
- 채택한 예산과 비교: 평균 60 FPS 이상 → **444.8 / 461.5 (통과)**, p95 25 ms 이하 → **6.77 / 6.31 ms (통과)**. 초당 FPS 최소값 move 353, combat 363.
- 원시 측정 증거: `results/evidence/perf/perf_move_1000_release.json`, `perf_combat_1000_release.json` (프레임 통계·초당 샘플·환경), `*.memory.json` (초당 워킹셋).
- 재현 편차 메모: 같은 빌드 설정으로 이 세션에서 먼저 돌린 1회차(메모리 샘플러 없음, 원시 파일은 2회차로 덮어씀)는 콘솔 기준 move 평균 301.6 FPS / p95 10.99 ms, combat 314.1 FPS / p95 10.79 ms 였다. 두 회차 모두 예산을 통과하지만 편차가 크므로, 예산 근접 판정이 필요해지면 3회 이상 반복 측정을 규칙으로 두는 것을 권한다.
- 관찰: p50 ≈1.4 ms 대비 p95 ≈6~11 ms로 프레임 시간이 이봉 분포다. 60 Hz sim step(1~2 ms) 외에 HUD 텍스트 재배치(6프레임마다, 한글 시스템 폰트)가 후보이나 **측정하지 않았다**. 예산에는 여유가 커서 이번 WP에서는 손대지 않았다 (알려진 문제 참조).

## 실제 화면 확인

재현 행동: `--capture` 모드가 정해진 시뮬레이션 시각에 뷰포트를 PNG로 저장하고 같은 순간의 상태를 JSON으로 남긴다. 모든 캡처는 HUD(동시 생존/생성 누계/처치/누수/경로별 생존/경로 버전/존 밀도/화차별 표적·발사·처치)를 포함한다.

| 캡처 | 관측 결과 |
|---|---|
| `ac01_t30_1000_alive_three_routes.png` | 전투 비활성, 동시 생존 1000. 남대문(적색)·서대문(청록)·동대문(황색) 세 흐름이 각 성문에서 광장을 거쳐 광화문 어귀(Z7 98)로 합류. 남대문 두 골목 모두 통행 |
| `ac02_a_reference_t30.png` → `ac02_b_west_lane_blocked_t30.png` | 같은 시드·시각. 장승 하나가 서편 골목을 막자 남대문 흐름 전체가 동편 골목으로 몰림(Z0 13→0, Z1 9→22). 화면에서 서편 골목이 비고 동편 골목이 두 배 밀도 |
| `ac02_c_restored_t42.png` | 제거 12초 후 서편 골목 재통행(Z0 19, Z1 20), 경로 버전 5 |
| `ac06_a_before_t35.png` → `ac06_b_after_t35.png` | 전투 활성. 전: 화차·중영이 Z0(27)을 사격, 처치 413. 후: 동편 골목에 55개체 압축, 화차·중영이 Z1을 사격해 같은 38발로 처치 1299, 남대문 누수 5→0. 사격선·폭발 링·표적 존 강조(주황)가 화면에 표시됨 |

캡처 경로: `results/evidence/captures/` (PNG 6장, JSON 로그 3개). 인터랙티브 플레이(창 실행, 마우스 설치·제거, C/R/Z/G 토글)도 세션 중 수동 확인했으나 별도 캡처는 남기지 않았다.

## 미해결 문제와 설계 변경 제안

1. **포화 골목의 장승 설치 성공률 (P-007, 설계 판단 필요)** — 재현: 전투 활성 30초 후 남대문 두 골목의 2×2 앵커 24곳을 0.1초 간격으로 스윕. 영향: 성공률 3.6~11.4%, 나머지는 전부 `ENEMY_OCCUPIES_CELL`. 규칙은 SYSTEM_SPEC대로 정확히 동작하지만 "병목을 만드는" 핵심 조작이 재시도에 의존한다. 우회: 인터랙티브 빌드는 마우스를 누르고 있는 동안 매 틱 재시도(보통 1~2초 내 성공); 스크립트 시나리오는 웨이브 도착 전(t=0)에 설치. 수정 후보: (a) 현행 유지, (b) 설치 시 점유 적을 인접 통행 셀로 밀어내기, (c) 설치 예약 후 셀이 비는 순간 확정. 게임 규칙 변경이므로 구현하지 않았다.
2. **서·동대문 남편 골목은 평시 미사용 (P-008)** — 목표가 북쪽이라 북편 골목이 항상 더 짧다. 남편 골목은 북편이 막힐 때만 쓰이는 우회로로 동작한다(AC-03 테스트로 검증). 의도된 우회로로 둘지, 지형을 바꿔 평시 분산을 만들지는 기획 판단.
3. **밸런스 초기값 (P-009)** — 피해 25·재장전 1.2s에서는 골목 통과(약 1.9초) 중 HP 60을 깎지 못해 골목 화차의 처치가 0이었다. 피해 34·재장전 0.8s로 "2발 처치"가 성립하게 맞췄다. 그 결과 남대문 누수가 거의 0이 되어 현재 값은 쉬운 편이다. 재미·난이도 튜닝은 범위 밖.
4. **프레임 시간 이봉 분포** — p95가 p50의 4~8배. HUD 텍스트 재배치가 의심되나 미측정. 예산 여유가 커서 보류. WP-002에서 HUD 갱신을 시간 기반(10 Hz)으로 바꾸고 재측정 권장.
5. **화차 통행 비차단 (D-011, GPT 확인 요청)** — SYSTEM_SPEC에 명시가 없어 GAME_DESIGN의 역할 분담을 따라 장승만 차단하도록 구현했다. 반대로 정하려면 `placement.gd`의 `blocking` 판정 한 줄이다.
6. **적 간 충돌 없음** — 적끼리 겹친다. 밀도는 위치 기반으로 정확히 집계되지만, 시각적 "밀집"은 겹침으로 표현된다. WP-001 범위에서 물리 충돌은 요구되지 않았다.
7. **플랫폼** — export 프리셋은 Windows x86_64만 정의했다. 다른 플랫폼은 O-001 후속.
8. **측정 편차** — 같은 설정에서 회차 간 평균 FPS 301 vs 445. 예산 근접 판정 시 반복 측정 규칙이 필요하다.

## 다음 WP 영향

- 재사용할 기능: `Battle` 오케스트레이터·고정 스텝·스냅샷, `DensityDetector`(센서 공유 시 존 카운트를 그룹 단위로 합치면 됨), `Placement`의 footprint·거절 사유 체계(봉수대 추가는 Kind 하나 추가), `Hwacha.select_zone`(공유 표적은 후보 영역 목록을 넓히는 방식으로 확장 가능), `PerfRecorder`·`--capture` 증거 파이프라인, 헤드리스 테스트 프레임워크.
- 변경된 인터페이스: 시설은 `Placement.Structure` 하나로 표현되고 `blocking` 플래그로 통행 차단 여부를 가른다. WP-002의 봉수대는 비차단 시설로 두면 경로 검증을 건드리지 않는다. 화차의 로컬 탐지 범위(`fire_range`)와 사격 범위를 SYSTEM_SPEC WP-002 규칙대로 분리하려면 `Structure`에 필드 하나를 더해야 한다.
- 주의점: (1) `path_version`은 차단 시설 변경에만 증가한다. 봉수망 연결 변경은 별도 버전 카운터를 두어야 한다. (2) 밀도 평가는 매 스텝 전체 적을 순회한다(8존 × 1000). 봉수망으로 존이 늘면 공간 해시 도입을 측정 후 검토. (3) 포화 골목 설치 규칙(P-007)은 WP-002/003의 재편 조작에도 그대로 영향을 준다 — 후퇴 시 내곽 재배치는 적이 도달하기 전에 이루어져야 성립한다. (4) 시뮬레이션은 결정적이지만 `--speed` 배속과 렌더 프레임은 무관하도록 유지해야 한다.

## 보완 회차 · 2026-09-13 (GPT REVISE R-01 / R-02 반영, Claude Code)

1차 제출(`7af1f92`)과 1차 GPT 리뷰(`0211f3d`, 아래 GPT Review 절)를 보존하고, 보완 구현 커밋 **`0f3a832`** 기준으로 다시 검증했다. 이 절의 증거 파일은 같은 경로에 덮어썼으며(캡처 PNG·JSON, test_report, 성능 JSON), 1차 성능 원시 파일은 덮어쓰기 전 수치를 위 "성능" 절과 재현 편차 메모에 그대로 남겼다.

### 변경 내용 (`0211f3d` → `0f3a832`)

| 파일 | 변경 | 대응 |
|---|---|---|
| `game/core/enemy_sim.gd` | `step_movement()`가 이동 **후** 위치로 `cell[s]`를 갱신. `is_cell_occupied()`는 캐시 대신 생존 적의 현재 좌표를 같은 floor 규칙으로 판정 | R-01 |
| `tests/test_path_and_placement.gd` | 회귀 케이스 추가: GPT 재현 좌표 (890,760.1) 1스텝 후 거절·path_version 불변, **진입 경계**(한 틱에 footprint로 들어옴 → 거절), **이탈 경계**(한 틱에 나감 → 수락), 포화 필드에서 커서 판정과 설치 판정이 24개 앵커 전부 일치. 포화 스윕은 고정 성공률 단언을 제거하고 측정치만 기록 | R-01 |
| `game/core/config.gd`, `battle.gd`, `scenes/main.gd` | 벤치마크 전용 `benchmark_hold_alive`(기본 false): 켜지면 매 틱 **끝**에 `target_alive`까지 즉시 보충. `--perf`가 켠다. 일반 플레이·캡처 시나리오의 생성 규칙은 그대로 | R-02 |
| `game/tools/perf_recorder.gd`, `scenes/main.gd` | JSON에 원시 프레임 간격 배열 `frame_us_raw`·`alive_raw`, `load_held_all_frames`, `path_version_expected`, 시설 수, 실행 인수 기록. 스크립트 모드(`--perf`, `--capture`)에서는 Esc 외 입력 무시 | R-02, 리뷰 권고 |
| `game/tools/probe_occupancy.gd` | 포화 스윕 + **홀드 대기시간** 측정(한 앵커를 누르고 있을 때 성공까지 틱 수) JSON 출력 | P-007 재측정 |
| `scripts/verify.ps1`, `verify.sh`, `perf_with_memory.ps1` | 각 단계 종료 코드·산출물 검사, 성능 합격 조건(avg≥60, p95≤25ms, alive_min≥target) 검사, 실패 시 즉시 중단 | 리뷰 권고 |
| `docs/SYSTEM_SPEC.md` | WP-001 절에 D-011(화차 점유는 중복 배치만 막고 통행은 막지 않음, 적은 footprint를 통과)과 "점유 판정은 현재 좌표 기준" 명시 | D-011 승인 반영 |
| `docs/DECISIONS.md`, `README.md` | P-007/P-008/P-009/D-011의 GPT 판정과 재측정치, 벤치마크 플래그·probe 설명 | — |

### AC 재검증 (보완 회차, 구현자 보고)

| AC | 보완 회차 | 실제 결과 | 증거 |
|---|---|---|---|
| AC-01 | PASS (변경 없음) | 캡처 재실행 t=30s: alive 1000 / spawned 2061 / leaked 1061, 경로별 297/352/351 — 1차와 동일 | `captures/ac01_*` |
| AC-02 | PASS (변경 없음) | 재실행 Z0 13→0→19, Z1 9→22→20, path_version 2→4→5 — 1차와 동일 | `captures/ac02_*` |
| AC-03 | **PASS (R-01 수정)** | GPT 재현 스크립트 재실행: `placement_accepted=false`, `reason=ENEMY_OCCUPIES_CELL`, `cached_cell=actual_cell=3596`, path_version 2→2. 진입 경계(y 760.05→759.70) 거절, 이탈 경계(y 720.2→719.7) 수락, 커서/설치 판정 불일치 0/24. 기존 전체 차단·정지 점유·지형·경계·중복 거절 유지 | `test_report.txt` "R-01 regression" 15건; `gpt-review/repro_occupied_after_move.gd` 재실행 출력(아래) |
| AC-04·05 | PASS (변경 없음) | 129/129 중 해당 케이스 전부 통과 | `test_report.txt` |
| AC-06 | PASS (변경 없음) | 같은 시드 창 [30,50]s: 24.8→44.1 밀도, 231→863 처치; 캡처 413→1299 — 1차와 동일 | `captures/ac06_*` |
| AC-07 | **PASS (R-02 보완 측정)** | 아래 표. **측정 프레임 전체에서 alive_min = 1000** (`load_held_all_frames=true`), 이동 전용·전투+경로 재계산 12회 모두 예산 충족 | `perf/perf_move_1000_release.json`, `perf_combat_1000_release.json`, `*.memory.json` |
| AC-08 | PASS | 절차 갱신(README, `scripts/verify.*` 검사 추가). 이 회차의 모든 증거를 같은 절차로 생성 | README, `scripts/` |

자동 검증: **129 passed / 0 failed** (24.6 s). GPT 재현 스크립트 출력(수정 후):
`{"actual_cell":3596,"cached_cell":3596,"footprint_contains_living_enemy":true,"placement_accepted":false,"reason":"ENEMY_OCCUPIES_CELL","path_version_before":2,"path_version_after":2}`

### 성능 보완 측정 (R-02) — 구현 커밋 `0f3a832`, 릴리스 빌드, 1920×1080, vsync off, 10s 준비 + 60s 측정

실행 인수: `hanyang_defense_wp001.exe -- --perf --scenario=<move|combat> --warmup=10 --measure=60 --out=<abs>.json` (`scripts/perf_with_memory.ps1` 경유, 외부 1 Hz 워킹셋 샘플). `--perf`는 `benchmark_hold_alive=true`를 켠다.

| 회차 | 시나리오 | 프레임 / 초 | 생존 min / avg / max | 부하 유지 | 평균 FPS | 프레임 ms p50 / **p95** / p99 / max | sim step ms avg / p95 / max | 경로 재계산 (path_version) | 워킹셋 MB 시작→종료 (최대) | 종료 코드 |
|---|---|---|---|---|---|---|---|---|---|---|
| **3 (채택)** | move | 25,338 / 60.00 | **1000 / 1000.0 / 1000** | true | **422.3** | 1.43 / **7.47** / 8.99 / 21.00 | 1.15 / 1.31 / 3.15 | 0 (2 = 기대 2) | 170.0→171.0 (171.0) | 0 |
| **3 (채택)** | combat | 25,242 / 60.00 | **1000 / 1000.0 / 1000** | true | **420.7** | 1.47 / **7.25** / 8.93 / 19.63 | 2.37 / 6.74 / 9.49 | 12 (14 = 기대 14), 화차 310발, 처치 8,281 | 171.7→172.8 (172.9) | 0 |
| 2 (참고) | move | 24,782 / 60.00 | 1000 / 1000.0 / 1000 | true | 413.0 | 1.46 / 7.69 / 8.97 / 14.93 | 1.27 / 1.39 / 9.19 | 0, 그러나 path_version 6 (기대 2) | 170.1→171.6 | 0 |
| 2 (참고) | combat | 22,571 / 60.01 | 1000 / 1000.0 / 1000 | true | 376.1 | 1.64 / 8.04 / 9.65 / 18.29 | 2.31 / 6.79 / 7.75 | 12, 그러나 path_version 50 (기대 14) | 168.5→171.6 | 0 |
| 1 (1차 제출) | move | 26,688 | 993 / 999.1 / 1000 | **false** | 444.8 | 1.42 / 6.77 / 8.63 / 40.26 | — | 0 | 167.7→171.1 | 0 |
| 1 (1차 제출) | combat | 27,693 | **931** / 993.5 / 1000 | **false** | 461.5 | 1.40 / 6.31 / 7.71 / 13.65 | — | 12 | 169.9→171.6 | 0 |

- 회차 3의 p95/p99/평균 FPS는 JSON의 `frame_us_raw`로 독립 재계산해 저장값과 일치함을 확인했다 (move p95 7.469, combat p95 7.248).
- 회차 2는 R-01/R-02 수정 직후의 측정으로 부하는 유지됐으나 `path_version`이 기대값과 달랐다(move +4, combat +36). 당시 `--perf` 모드가 창의 마우스·키 입력을 그대로 받아들여 측정 중 전면 창에 들어온 입력이 장승 설치·제거를 일으킨 것으로 판단하고, 스크립트 모드의 입력을 차단한 뒤 회차 3으로 대체했다. 회차 2 원시 파일은 `perf/*_run2_unguarded_input.json`으로 남긴다(예산 자체는 충족하지만 채택하지 않음).
- 예산 대비: 평균 60 FPS 이상 → 422.3 / 420.7 (통과), p95 25 ms 이하 → 7.47 / 7.25 ms (통과), 동시 1,000 유지 → alive_min 1000 (통과). 초당 FPS 최소값 move 299, combat 246.
- 메모리: 60초 동안 워킹셋 증가 ≤1.1 MB. 장기 누수 여부는 60초 관측으로 단정하지 않는다.

### P-007 재측정 (R-01 수정 후, `results/evidence/occupancy_probe.json`)

- 포화 스윕(전투 활성 30초 후, 남대문 두 골목 24개 앵커, 0.1초 간격 100회): **65/2400 = 2.71%** 수락, 나머지 전부 `ENEMY_OCCUPIES_CELL`. 테스트 내 30회 스윕: 38/720 = 5.28% (GPT 재실행과 동일).
- **홀드 대기시간**(한 앵커를 누르고 매 틱 재시도, 20회 시행): 19회 성공, 1회 30초 내 실패. 성공까지 **최소 1.08 s / 평균 7.66 s / 최대 25.58 s**.
- 해석: 규칙은 명세대로 동작하며 1차 보고의 "3.6~11.4%"는 캐시 오류로 부풀려진 값이었다. 실제 대기 평균 7.7초는 전투 중 재편 조작으로는 길다. GPT 판정대로 WP-001에서는 현행 규칙을 유지하고, "예약 → 빈 순간 재검증 후 확정"은 별도 명세 후 후속 WP에서 다룬다.

### 이 회차의 알려진 문제

- 프레임 시간 이봉 분포(p50 ≈1.4 ms, p95 ≈7.5 ms)는 그대로이며 원인(HUD 재배치 추정)은 여전히 미측정.
- `benchmark_hold_alive`는 벤치마크 전용이다. 이를 켠 상태의 처치 수(8,281/60s)는 즉시 보충 때문에 일반 플레이보다 높다.
- 회차 2의 입력 유입 원인은 정황 판단이다(입력 차단 후 회차 3에서 기대값과 일치). 이후 모든 스크립트 실행은 입력을 무시한다.

### 재리뷰 요청

R-01 수정 및 양쪽 경계 회귀, P-007 재측정, R-02 부하 유지 측정, SYSTEM_SPEC D-011 명시를 반영했다. GPT 재리뷰에서 AC-03·AC-07을 다시 판정해 주기를 요청한다. 최종 판정은 아래 GPT Review 절에 날짜별로 추가한다.

## GPT Review

### 2026-09-13 · 최종 판정: **REVISE**

- 검토자: GPT / Codex.
- 코드 비교: `17d17e9c685bcfd9a1007f7c36aca0daeaf572db` → `7af1f9288a26bcf8f43fdb091f8de1f2be83b4b1`.
- 제출 결과·증거 기준: PR #1의 `ac712a32d2aaa8ad4889925bfbd192f3023a45cc`. 구현 이후 커밋이 결과 문서와 증거만 추가한 것을 확인했다.
- 위 Acceptance Criteria 표는 구현자의 최초 보고로 보존한다. 아래 표가 GPT 검토 판정이며, 기존 116/116 통과만으로 AC 전체를 승인하지 않는다.
- 판정 합계: **PASS 6 / FAIL 1 / NOT RUN 1**. WP는 REVIEW를 유지한다. 병합·DONE 전환·WP-002 착수는 보완 후 재검토한다.

### AC별 판정

| AC | GPT 판정 | 검토 증거와 판단 |
|---|---|---|
| AC-01 | **PASS** | 제출 ac01 PNG·JSON에서 alive=1000, spawned=2061, leaked=1061, killed=0, 세 경로 297/352/351을 대조했다. 새 체크아웃의 자동 검증에서도 같은 집계가 재현됐다. |
| AC-02 | **PASS** | 제출 ac02 PNG 3장과 JSON의 Z0 13→0→19, Z1 9→22→20 및 path_version 2→4→5를 확인했다. 리뷰에서 `--capture=ac02`를 실행해 같은 시점의 alive·처치·누수·steps·path_version을 재현했다. 사전 배치 후 우회·제거 복원은 입증됐지만, 포화 전투 중 성공률은 별도 P-007 문제다. |
| AC-03 | **FAIL** | 전체 경로 차단·정지한 적 점유·중복 배치 거절은 통과한다. 그러나 이동 직후 캐시가 이전 셀을 가리켜 실제 점유 셀에 장승 설치가 허용된다. 아래 R-01에서 기본 설정 한 스텝으로 재현했다. |
| AC-04 | **PASS** | 내부·정확한 반경 경계·외부 좌표 및 사망 즉시 제외 테스트를 재실행했다. `density_detector.gd`의 현재 생존 목록과 `<= radius²` 조건이 명세와 일치한다. |
| AC-05 | **PASS** | 최고 밀도·사거리 경계·동률 ID·빈 표적·피해 및 사망 1회 집계 테스트를 재실행했다. 같은 틱의 후속 화차가 앞선 처치 후 밀도를 다시 평가하는 코드도 확인했다. |
| AC-06 | **PASS** | 같은 시드/시간 창의 평균 밀도 24.8483→44.1333, 중영 화차 처치 231→863, 남대문 도달 2→0이 재실행에서 재현됐다. 제출 ac06 전후 PNG·JSON의 38발/413→1299처치도 확인했다. 사전 배치의 효과를 입증하며 전투 중 설치 UX 전체를 입증하지는 않는다. |
| AC-07 | **NOT RUN** | 제출 측정은 실행되었고 FPS·p95 수치 자체는 통과다. 다만 D-009가 채택한 동시 1,000개체 부하를 측정 구간 내내 유지한 검증은 없다. 이동 min/avg=993/999.07, 전투=931/993.52로, 이 표의 NOT RUN은 정확한 요구 부하 검증이 미실행이라는 뜻이다. 성능 실패라고 단정하지 않는다. R-02의 보완 측정이 필요하다. |
| AC-08 | **PASS** | 별도 새 체크아웃에서 Godot 4.7 표준 테스트 116/116, ac02 창 실행·캡처·JSON 생성, Windows 릴리스 export 종료 0과 독립 exe의 2초 실행·종료를 확인했다. 리뷰에서는 전체 일괄 스크립트와 70초 성능 두 시나리오를 다시 실행하지 않았다. 정상 경로의 재현 가능성 판정이며 AC-07 승인을 대신하지 않는다. |

### R-01 · 필수 수정: 이동 후 점유 캐시 갱신 (AC-03)

- 위치: `game/core/enemy_sim.gd:177-178,202-204,251-254`, `game/core/placement.gd:154-157`. `main.gd`는 물리 스텝 이후에도 설치를 시도한다.
- 원인: `step_movement()`가 이동 전 위치로 `cell[s]`를 저장한 뒤 위치만 변경한다. `is_cell_occupied()`는 이 캐시를 읽고, `refresh_cells()`는 정상 설치 경로에서 호출되지 않는다.
- 재현: 기본 시드, 전투·추가 생성 비활성. 남대문 적 1체를 `(890,760.1)`에 생성하고 기본 dt 한 스텝 이동한 뒤 장승을 `(44,36)`에 설치한다.
- 실제: 위치 `(890.897888,759.646545)`, 현재 셀 **3596**은 설치 footprint 안인데 캐시 **3692**는 밖이다. 설치가 `ok=true / NONE`으로 수락되고 path_version이 **2→3**으로 변한다.
- 기대: 현재 위치를 기준으로 `ENEMY_OCCUPIES_CELL` 거절. 시설 수·통행 상태·dist/flow·path_version 불변.
- 수정 요구: 이동 완료 시점 또는 명령 검증 시점에 점유 정보를 현재 좌표와 일치시킨다. 시각 오버레이의 가능/불가능 판단도 같은 기준을 사용한다. 적이 footprint에 들어오는 경계와 빠져나가는 경계 양쪽을 회귀 검증한다. 적을 강제로 밀어내는 것으로 이 버그를 우회하지 않는다.
- 증거: [재현 스크립트](evidence/gpt-review/repro_occupied_after_move.gd), [관측 출력](evidence/gpt-review/occupancy_repro.txt). 실행: `godot --headless --path . --script res://results/evidence/gpt-review/repro_occupied_after_move.gd`. 이 스크립트의 종료 0은 관측 완료이며 AC 통과를 의미하지 않는다.

### R-02 · 필수 보완: 성능 측정 부하 증명 (AC-07)

- JSON의 평균 FPS를 frames/measured_seconds로 재계산했으며 move **444.7655**, combat **461.5425**로 일치한다. 저장된 p95는 각각 **6.771 / 6.312 ms**이며 구현의 nearest-rank 계산을 확인했다. 원시 프레임 배열은 저장되어 있지 않아 p95 자체를 독립 재계산하지는 못했다.
- 1920×1080, exported release, vsync=0, 10초 준비+약 60초 측정, combat 경로 재계산 12회 기록을 확인했다. 외부 메모리 로그는 move 167.7→171.1 MB, combat 169.9→171.6 MB, 종료 코드 0이다. 60초 관측은 장기 메모리 누수 부재의 증명이 아니다.
- 동시 생존 1,000이라는 채택 조건을 target_alive=1000 설정만으로 대체하지 않는다. 벤치마크 전용 보충 또는 충분한 부하 여유로 측정 프레임의 alive_min≥1000을 확보하고, 이동/전투+경로 변경 각각 같은 예산으로 다시 측정한다. 일반 게임의 밸런스·생성 규칙은 바꾸지 않아도 된다.
- 새 증거에는 검증한 구현 커밋, 정확한 실행 인수·설정, 실제 부하 min/avg/max, 측정 시간, FPS/p95, 경로 재계산 횟수, 메모리와 종료 코드를 남긴다. 기존 수치를 삭제하지 말고 보완 회차로 구분한다. 요구 부하를 충족하지 못하면 통과 처리하지 않는다.

### 기획 판단

**P-007 — 현행 점유 거절 규칙은 WP-001에서 유지, 설치 예약은 후속 제안으로 권고.** 먼저 R-01을 고치고 포화 골목 성공률과 실제 입력 후 대기 시간을 다시 측정한다. 리뷰 재실행의 스윕은 38/720(5.28%)로, 기존 보고의 82/720과 다르므로 3.6~11.4%를 고정 보장치로 쓰지 않는다. 핵심 재미인 전투 중 재편을 위해서는 ‘선택 위치에 예약 → 빈 순간 재검증 후 확정’이 무작정 홀드하는 것보다 의도를 잘 보존한다. 단, 예약의 취소·상태 표시·확정 시 경로/중복/점유 재검증을 별도 명세로 정한 뒤 구현한다. 밀어내기 방식은 적 흐름을 즉시 바꾸는 전투 능력이므로 이번 수정에 섞지 않는다. AC-02/06의 사전 배치 PASS를 현장 개입 UX의 완성으로 해석하지 않는다.

**D-011 — WP-001 한정 승인.** 장승은 흐름 제어, 화차는 화력을 담당하는 역할 분리가 핵심 가설을 명확하게 만든다. 화차의 2×2 점유는 다른 시설과의 중복 배치를 막지만 적 통행은 막지 않는다고 SYSTEM_SPEC에 명시한다. 실제 코드는 적이 화차 footprint를 통과하므로 ‘화차 주변으로 회피한다’고 설명하지 않는다. 최종 아트는 길 가장자리/높은 플랫폼 등으로 이를 이해하기 쉽게 표현할 수 있다. 봉수대의 통행 규칙까지 자동 확정한 것은 아니다.

**P-009 — 재현용 프로토타입 초기값으로 승인.** HP 60, 피해 34, 재장전 0.8초, 반경 55, 사거리 200은 병목 형성 후 집중 사격의 효과를 관찰하는 데 적합하다. 수치가 설정으로 분리되고 동일 설정의 전후 비교가 있어 자의적인 수용 기준 완화로 보지 않는다. 다만 남대문 누수가 0에 가까운 현재 시나리오는 출시 난이도나 ‘2발이면 항상 처치’의 보장이 아니다. 사거리 체류시간·재장전 시작 상태에 따라 결과가 달라지며, 재미/경제/웨이브 밸런스는 후속 검증한다.

P-008의 서·동대문 남편 골목은 WP-001에서는 의도된 우회 선택지로 수용한다. 세 진입로 사용과 각 진입로 내부의 평시 분산은 다른 요구다.

### 증거 범위와 다음 검토

- 범위 준수: Godot 2D 회색상자로 흐름·밀도·화차 가설에 집중했고, 봉수망·경제·보스·최종 그래픽을 구현하지 않았다. 모듈 역할 분리와 데이터 기반 초기값은 후속 확장에 적합하다.
- 제출 PNG 6장을 직접 확인했다. 회색상자의 경로와 밀도 비교는 읽을 수 있으나 콘셉트 아트 수준의 완성도는 이번 합격 조건이 아니다.
- 리뷰 추가 증거: [자동 테스트 재실행](evidence/gpt-review/test_report.txt), [ac02 재현 상태](evidence/gpt-review/ac02_recheck.json). 원 제출 증거를 덮어쓰지 않았다. 캡처 재실행 PNG와 빌드 산출물은 로컬 검토용이며 새 배포물로 게시하지 않았다.
- 환경 제한 메모: 최초 샌드박스 실행은 Godot 사용자 로그 경로 접근 실패로 중단됐다. 정상 사용자 환경에서 같은 엔진으로 다시 실행해 테스트·캡처·export를 확인했으며, 최초 중단을 게임 결함으로 세지 않았다.
- 추가 개선 권고: `scripts/verify.ps1:21-36`은 테스트 이후 외부 명령의 종료 코드와 산출물을 확인하지 않으며, `perf_with_memory.ps1`은 종료 코드를 기록만 한다. export/캡처 실패 시 즉시 중단하고 JSON·PNG 생성 및 합격 조건을 확인하도록 보강하는 편이 좋다. 현재 정상 경로의 AC-08 PASS와 구분한다.
- 재검토 순서: R-01 수정 및 경계 회귀 → P-007 재측정 → R-02 부하를 만족하는 성능 증거 → 결과 문서·SYSTEM_SPEC의 D-011 명시 → GPT 재리뷰. 이번 검토에서는 게임 코드를 수정하거나 PR을 병합하지 않았다.

이 문서는 구현·테스트 결과 기록이며, DONE 전환은 모든 필수 AC 충족과 GPT PASS 이후에만 한다.
### 2026-09-13 · 보완 재리뷰 (2차) · 최종 판정: **PASS**

- 검토자: GPT / Codex. 코드 diff `0211f3d561a6ec7eccb8d7fe7e73779b02043d7a` → `0f3a8328eb722bb51fdc2c8a55664175448bb5e8`, 보완 결과·증거 `5cc178e2d49030b9f4180f0bcf0994d5c4010a0c` 기준. 후자는 문서·증거 변경이며 추가 게임 코드 변경은 없다.
- **PASS 8 / FAIL 0 / NOT RUN 0.** R-01과 R-02를 해소했다. 위 1차 REVISE 기록은 이력으로 보존하며 최신 판정은 이 절이다. WP-001의 GPT 승인 조건을 충족했다. 이 리뷰 커밋은 판정·증거만 기록하며 PR 병합과 WP 상태 전환은 수행하지 않았다.

| AC | 최신 GPT 판정 | 근거 |
|---|---|---|
| AC-01 | **PASS 유지** | 전체 테스트 재실행에서 동시 1000, 세 경로 297/352/351과 생성 집계가 재현됨. 일반 플레이의 보충 설정 기본값은 변경되지 않음. |
| AC-02 | **PASS 유지** | 재실행에서 장승 우회와 제거 후 복원 통과. 해당 경로 알고리즘은 이번 diff에서 변경되지 않음. |
| AC-03 | **PASS (FAIL 해소)** | 지정 재현 스크립트를 재실행해 현재/캐시 셀 3596, 설치 거절 ENEMY_OCCUPIES_CELL, path_version 2→2 확인. 제출·재실행 리포트의 R-01 회귀 15개 단언 모두 PASS. |
| AC-04 | **PASS 유지** | 밀도 경계·사망 제외 자동 검증 재통과. |
| AC-05 | **PASS 유지** | 최고 밀도 선택·동률·빈 표적·피해·중복 처치·쿨다운 자동 검증 재통과. |
| AC-06 | **PASS 유지** | 동일 조건에서 밀도 24.8483→44.1333, 중영 화차 처치 231→863, 남대문 도달 2→0 재현. |
| AC-07 | **PASS (NOT RUN 해소)** | 채택 회차 move/combat JSON의 alive_raw와 frame_us_raw 독립 검산. 전체 프레임 alive=1000, 평균 FPS≥60, p95≤25ms. 아래 표 참조. |
| AC-08 | **PASS 유지** | 별도 리뷰 체크아웃에서 Godot 4.7 재현 및 전체 테스트 종료 0. 이전 새 체크아웃·캡처·export 검증에 더해 변경된 실행/측정 절차를 코드 검토함. 이번 리뷰에서 전체 캡처·export·70초 성능 측정은 재실행하지 않음. |

#### AC-03 · 수정과 재현 확인

`step_movement()`는 이동 후 캐시를 갱신하고 `is_cell_occupied()`는 생존 적의 현재 좌표로 직접 판정한다. 배치와 overlay가 같은 함수를 사용한다. 점유 거절은 지형/시설/경로 변경 전에 반환되므로 dist·flow·통행·시설 수가 보존된다(거절 집계와 last_result 갱신은 의도된 진단 상태다).

- 지정 스크립트 실제 관측: 위치 `(890.897888,759.646545)`, `actual_cell=cached_cell=3596`, `footprint_contains_living_enemy=true`, `placement_accepted=false`, `reason=ENEMY_OCCUPIES_CELL`, `path_version_before=path_version_after=2`.
- R-01 회귀 15건: 정확한 재현 위치, 진입한 틱 거절, 이탈한 틱 수락, 포화 24개 앵커 점유/설치 일치 확인. 이는 15개 독립 시나리오가 아니라 해당 회귀 절의 15개 단언이다. 보완 설명의 이탈 y≈719.7은 실제 제출·재실행 로그 **719.843**으로 읽는다(판정에는 영향 없음).
- 전체 테스트 **129 passed / 0 failed**, 리뷰 실행 **22.9초**, 종료 코드 **0**. 기존 전체 차단 거절 시 dist/flow/시설/경로 상태 보존도 재통과했다.
- 재현 스크립트의 종료 0 자체가 합격을 뜻하지 않으므로 위 JSON 값을 직접 확인했다.

#### AC-07 · 원시 자료 독립 검산

채택한 `perf_move_1000_release.json`과 `perf_combat_1000_release.json`만 합격 근거로 사용한다. 경로 버전이 어긋난 `*_run2_unguarded_input.json`은 참고 이력으로 제외한다.

| 시나리오 | 원시 프레임/생존 샘플 수 | 원시 간격 합계(초) | 재계산 FPS | 재계산 p95(ms) | alive min/avg/max | load_held_all_frames | 경로 재계산 / 버전 |
|---|---|---|---|---|---|---|---|
| move | 25,338 / 25,338 | 60.002198 | 422.284530 | 7.469 | 1000 / 1000 / 1000 | true | 0 / 2=기대 2 |
| combat | 25,242 / 25,242 | 60.000723 | 420.694931 | 7.248 | 1000 / 1000 / 1000 | true | 12 / 14=기대 14 |

계산: FPS = `len(frame_us_raw) * 1,000,000 / sum(frame_us_raw)`. p95 = 정렬한 원시 간격의 `ceil(0.95*N)-1` 인덱스 값 / 1000(nearest-rank). 모든 간격은 양수이며 원시 배열 길이·시간·FPS·p95·생존 최소/평균/최대가 저장 요약과 일치한다. 저장된 true만 신뢰하지 않고 alive_raw 전부가 1000인지 검증했다.

메타데이터는 exported release, Godot 4.7, 1920×1080, vsync=0, 준비 10초 + 측정 60초, target=1000, benchmark_hold_alive=true를 나타낸다. 외부 메모리 리포트 종료 코드는 양쪽 0이다. 틱 끝에 실제 개체를 보충하고 렌더 프레임에서 실제 alive_count를 기록하는 코드이며, 카운터만 1000으로 고정한 구현이 아니다. 보충 비용도 다음 프레임 간격에 포함된다. 기본 플래그 false 및 --perf 전용 활성화를 확인하여 일반 플레이 밸런스와 분리된 측정으로 수용한다.

이 판정은 제출 릴리스 측정의 원시 자료 검산이며 리뷰어가 성능 측정을 다시 실행한 결과는 아니다. 해당 장비·60초·두 시나리오 범위의 성능 승인이고, 장기 누수·다른 장비·5000개체 성능 보장은 포함하지 않는다.

#### 기획 판단과 비차단 후속 항목

- **P-007:** WP-001의 현재 좌표 점유 거절 규칙 유지. 제출 스윕 65/2400(2.71%), 홀드 20회 중 19회 성공/1회 30초 제한 초과, 성공 표본 평균 7.66초는 전투 중 재편의 사용성 과제로 남긴다. 평균은 실패 표본을 제외한 값이므로 전체 평균 대기시간이라고 해석하지 않는다. 예약 설치는 취소·상태 표시·확정 시 재검증을 명세한 후속 작업으로 다룬다. 이번 AC PASS가 재편 UX의 완성을 뜻하지 않는다.
- **D-011:** 화차의 시설 중복 점유와 적 통행 비차단을 SYSTEM_SPEC에 명시한 것을 확인했다. WP-001 한정 승인 유지.
- **P-009:** 프로토타입 초기값 승인 유지. benchmark_hold_alive의 즉시 보충 상태에서 얻은 처치 수는 일반 게임의 경제·난이도 밸런스 자료로 사용하지 않는다.
- **검증 스크립트:** PowerShell 경로에 종료·산출물·성능 예산 검사가 추가됐다. 다만 보완 표의 설명과 달리 verify.sh에는 FPS/p95/부하 합격 조건 검사가 없고, 기존 산출물이 있으면 존재 검사만으로 새 생성 여부를 증명하지 못한다. 다음 운영 정리에서 두 스크립트 검사 수준과 산출물 신선도 검사를 맞추기를 권고한다. 이번 제출 원시 자료는 직접 검산했으므로 이번 AC 판정의 차단 사유는 아니다.

리뷰 추가 증거(이전 리뷰 파일과 제출 증거를 보존): [점유 재현 출력](evidence/gpt-review/2026-09-13-followup/occupancy_repro.txt), [전체 테스트 재실행](evidence/gpt-review/2026-09-13-followup/test_report.txt), [성능 독립 검산](evidence/gpt-review/2026-09-13-followup/perf_recalculation.json).
