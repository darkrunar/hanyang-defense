# WP-001 Result

- 작성일: 2026-09-13
- WP / 상태: WP-001 Enemy Flow Prototype / **REVIEW** (GPT 판정 PENDING)
- 기준 커밋: `17d17e9c685bcfd9a1007f7c36aca0daeaf572db` (origin/main, "docs: add concept art and gameplay mockup references")
- 검증한 구현 커밋: `7af1f9288a26bcf8f43fdb091f8de1f2be83b4b1` ("feat(wp-001): Godot 4.7 enemy flow prototype …")
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

## GPT Review

- 검토일 / 검토한 구현 커밋: (PENDING) / `7af1f92`
- 최종 판정: **PENDING**
- 기준별 검토 결과: (PENDING)
- 범위 준수 / 기획 일치 / 증거 충분성: (PENDING)
- 보완 요청 또는 다음 WP 준비 사항: (PENDING) — 특히 P-007(포화 골목 설치 규칙), D-011(화차 비차단), P-009(밸런스 초기값)에 대한 판단을 요청한다.

이 문서는 구현·테스트 결과 기록이며, DONE 전환은 모든 필수 AC 충족과 GPT PASS 이후에만 한다.
