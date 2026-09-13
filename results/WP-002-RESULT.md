# WP-002 Result

- 작성일: 2026-09-14
- WP / 상태: WP-002 Bongsu Network / **REVIEW** (GPT 판정 PENDING)
- 기준 커밋: `37c29f1` ("docs(wp-002): finalize bongsu network criteria and mark READY", main; WP-001 DONE 머지 `a8f16ef` 포함)
- 검증한 구현 커밋: `efa53bb8ae162624773ab979c45285c7b1754605` ("feat(wp-002): bongsu network …")
- 브랜치: `wp/002-bongsu-network` · Draft PR: https://github.com/darkrunar/hanyang-defense/pull/2
- 실행 환경 / 엔진·버전: Godot 4.7.stable.official.5b4e0cb0f (GDScript, 2D, gl_compatibility / OpenGL 3.3) · Windows 11 Home 10.0.26200 · AMD Ryzen 5 7600 (6C/12T) · NVIDIA GeForce RTX 4070 SUPER (driver 591.86) · 63.2 GB RAM · 1920×1080 · Parsec 가상 디스플레이 어댑터 공존(vsync off로 측정)

이 문서는 `results/RESULT_TEMPLATE.md` 양식을 따른다. 수치는 전부 `results/evidence/wp-002/` 원시 파일에서 가져왔고, WP-001 증거(`results/evidence/`)는 손대지 않았다. 문서 커밋은 구현 커밋과 분리한다.

## 구현 결과

계약 문서는 [backlog/WP-002.md](../backlog/WP-002.md)(READY `37c29f1`)와 DECISIONS D-012~015다. 수치·정책은 완화하지 않았다. 구현자가 결정한 자료구조·모드 분리는 D-016~018에 기록했고, 계약을 그대로 충족할 수 없었던 항목 하나(fixture A의 로컬 사격 기하)는 P-010으로 제안했다.

### 변경 파일과 각 변경 목적

| 파일 | 목적 |
|---|---|
| `game/core/bongsu_network.gd` (신규) | 활성 봉수대 간선(중심 거리² ≤ 180², 격자 좌표라 정수 비교로 경계 정확), 연결 요소(그룹 id = 최소 봉수대 id), 단말 최근접 부착(동률 id 오름차순, 단말 비중계), 매 틱 센서 탐지(140px)·화차 인지 집합(로컬 100px ∪ 같은 그룹 센서), 개체 id 키로 중복 제거, `topology_version`, 스냅샷 |
| `game/core/enemy_sim.gd` | 슬롯별 세대 카운터 `gen`; `enemy_id = gen<<16 | slot`, `is_id_alive()` (D-017) |
| `game/core/placement.gd` | `Kind.BONGSU`/`SENSOR`(2×2, 통행 비차단, 같은 배치 검증), `active`(비활성은 점유 유지·기능 중단), `detect_range`, `attached_to`, `group_id`, 표적 출처·대기 이유 진단 필드, `of_kind()`, `set_active()`, `kind_name/label` |
| `game/core/hwacha.gd` | wp002 모드: 화차별 인지 집합으로 후보 영역 밀도 계산(같은 틱 앞 화차의 처치 제외), `shared_only_shots`, 볼리별 로컬/공유 출처, 대기 이유. wp001 모드는 기존 전역 밀도 경로 그대로 |
| `game/core/battle.gd` | 틱 순서 생성→이동→전역 밀도→망 재계산(명령으로 dirty)→탐지→사격→벤치마크 보충. fixture `wp001`/`b`/`none`, `place_structure/remove_structure/set_active/toggle_active_at_world`, 명령 집계, 확장 스냅샷(망·화차별 인지 id) |
| `game/core/config.gd` | `targeting_mode`(기본 wp002), `fixture`(기본 b), `bongsu_link_range` 180, `sensor_range` 140, `hwacha_local_range` 100, `Config.for_wp001()` (D-018) |
| `game/maps/hanyang_test_map.gd` | fixture B 봉수대 8·센서 4 앵커, fixture A 앵커·적 좌표 |
| `game/scenes/main.gd` | 키 3/4 봉수대·혼천의 설치, T 활성 전환, HUD 봉수망 줄(모드·간선·그룹·위상·공유전용 사격·화차별 로컬/공유), `--capture=wp002_a`, `--perf --scenario=network_move|network_combat`(B8 전환·장승 (22,28) 12회, 거절 재시도·집계), 성능 JSON 확장(시설 수·망 스냅샷·기대값·공유전용 사격·첫 공유 사격 시각). WP-001 시나리오(`ac0*`, `move/combat`)는 wp001 구성으로 고정 |
| `game/scenes/overlay_layer.gd` | 봉수대(불꽃)·혼천의(고리) 아이콘, 간선(주황 실선)·부착선(점선), 센서 140·로컬 100·연결 180 반경, 비활성 회색, 그룹 태그, 커서 아래 시설 정보 패널(부착·그룹·로컬/공유 인지·표적 출처·대기 이유), 부착선 강조 |
| `tests/test_bongsu_network.gd` (신규), `tests/run_tests.gd` | AC-01~05·AC-07·결정성·초기화 검사 138건 |
| `tests/test_*.gd`(WP-001), `game/tools/*.gd` | `Config.for_wp001()`로 고정 → WP-001 회귀 135건 결과 동일 |
| `scripts/verify.ps1`, `verify.sh`, `perf_with_memory.ps1` | 4b fixture A 캡처, 6b fixture B 성능(계약 검사: avg/p95/부하, B8 12, 장승 12, pv 기대값, 공유전용 사격 ≥1), 산출물 삭제 후 재생성, network 시나리오 허용 |
| `docs/DECISIONS.md`, `README.md`, `backlog/WP-002.md`, `docs/ROADMAP.md` | D-016~018, P-010·P-011, WP-002 실행·조작 절, 상태 REVIEW |

## 실행·재현 절차

필요 도구: Godot 4.7.stable(`godot` PATH), Windows export template(빌드·성능), PowerShell(성능 메모리 샘플러). 추가 패키지 없음.

```bash
git clone https://github.com/darkrunar/hanyang-defense.git && cd hanyang-defense && git checkout wp/002-bongsu-network
```

| 단계 | 명령 | 산출물 |
|---|---|---|
| 자동 검증(WP-001 회귀 + WP-002) | `godot --headless --path . --script res://tests/run_tests.gd -- --report=<abs>/results/evidence/wp-002/tests/test_report.txt` | 종료 코드 0, 273/273 |
| fixture A 캡처 | `godot --path . --rendering-driver opengl3 -- --capture=wp002_a --out-dir=<abs>/results/evidence/wp-002/captures` | PNG 5장 + `wp002_a_log.json` |
| 릴리스 빌드 | `godot --headless --path . --export-release "Windows Desktop Release" build_out/windows/hanyang_defense_wp001.exe` | 단일 exe |
| fixture B 성능 | `.\scripts\perf_with_memory.ps1 -Scenario network_move\|network_combat -Warmup 10 -Measure 60 -Out results\evidence\wp-002\perf\perf_<sc>_1000_release.json` | 프레임 JSON(원시 배열 포함) + `.memory.json` |
| 일괄 | `.\scripts\verify.ps1` (`-Quick`: 빌드·성능 제외) / `scripts/verify.sh` | WP-001 단계 + 4b/6b |
| 플레이 | `godot --path . --rendering-driver opengl3` | 기본 wp002 + fixture B. 조작은 README |

설정: 시드 `20260913`, 연결 180 / 센서 140 / 로컬 100 / 사거리 200 px, 피해 34 / 재장전 0.8s / 폭발 55 (WP-001 유지), 고정 스텝 60 Hz. fixture A는 `fixture=none`, `enemy_speed=0`, 생성 끔, 전투 켬. 성능은 `benchmark_hold_alive=true`(벤치마크 전용, 일반 플레이 생성 규칙 불변). 모드는 모든 증거 JSON의 `targeting_mode`/`fixture` 필드에 기록된다.

## Acceptance Criteria

| AC | PASS / FAIL / NOT RUN | 기대 결과 | 실제 결과 | 증거 파일·로그·화면 |
|---|---|---|---|---|
| AC-01 | **PASS** | 활성 봉수대 연결 요소와 단말 단일 부착이 계약과 일치 | 정확히 180px(660,380)-(840,380) 연결, 181.1px 비연결; 다중 홉 s1–s2–s3(320px 떨어진 s1·s3 같은 그룹); 삼각 순환 간선 3·그룹 1; 비활성 중계 시 분리·그룹 -1·복구 시 재결합·위상 버전 증가; 센서 최근접 부착, 화차 동률(144.2/144.2)은 낮은 id, 180px 정확 부착·184.4px 비부착, 변화 시 재부착; 두 망 사이 센서는 한쪽에만 부착하고 병합하지 않으며 양쪽 200px 화차는 미부착, 다른 그룹 센서 탐지가 화차에 전달되지 않음 | `wp-002/tests/test_report.txt` "AC-01" 3케이스 34건 |
| AC-02 | **PASS** | fixture A: 비연결 0발 → 연결 1발 이상, 같은 위치·시드·초기 쿨다운 | 헤드리스: H↔적 155.24px(로컬 밖·사거리 안), S↔적 50px. B 비활성 3초: 인지 0·발사 0·대기 "표적 없음"·쿨다운 0 유지 → B 활성 다음 틱: 공유 1·로컬 0·**발사 1**·표적 Z0·출처 공유·공유전용 사격 1·적 HP 60→26(피해 보너스 없음). 캡처: a1(t=2.0) 인지 0/발사 0 → a2(t=2.5) 그룹 [2], 공유 1, 발사 1 | 테스트 "AC-02" 14건; `captures/wp002_a1_*.png`, `wp002_a2_*.png`, `wp002_a_log.json` |
| AC-03 | **PASS** | 단절·센서 소멸/이탈·사망을 다음 발사 전에 반영, 복구 시 재획득, 로컬 사격 유지, 슬롯 재사용, 쿨다운 비초기화 | 발사 후 B 비활성 → 2초(재장전 0.8s 초과) 추가 발사 0, 쿨다운은 정상 소진(0.0, 초기화 없음), 인지 0; 단절 중 보조 화차 H2(로컬 90px)가 로컬 적에 1발(출처 로컬), H는 여전히 1발; B 복구 → 1초 내 재발사. 출처 소실: 센서 2개 중 1개 비활성 → 유지, 2개 모두 → 즉시 폐기, 복구 → 재획득; 범위 이탈 → 폐기, 복귀 → 재획득; 사망 → 미인지; 같은 슬롯 재사용 개체는 새 id로 미인지, 옛 id는 사망. 캡처 a3(t=5.0, 준비 완료 2.5초 경과) 발사 1 유지, a4(t=5.5) H2 로컬 1발·H 0추가, a5(t=7.0) 복구 후 H 2발·처치 | 테스트 "AC-03" 2케이스 30건; `captures/wp002_a3_*`, `a4_*`, `a5_*`, 로그 |
| AC-04 | **PASS** | 다른 그룹 정보·사거리 밖 표적 미사용, 정확 경계, 부분 관측 | 센서 140.0 감지·140.5 미감지, 로컬 100.0 감지·100.5 미감지; 분리망(Z5에 5체)은 무시하고 자기 그룹 Z0(1체) 사격; 2홉 중계로 알게 된 Z2 3체는 사거리 400px 밖 → 발사 0, 대기 "알려진 표적이 사거리 밖"; Z7 전역 밀도 2 vs 화차 집계 1(숨은 적 미집계) | 테스트 "AC-04" 23건 |
| AC-05 | **PASS** | 중복 센서·로컬 중복·순환망 비증폭, 앞 화차 처치 제외 | 센서 1개/2개/순환 3봉수대: 인지 6·존 6·2초 발사 2·처치 6 모두 동일; 로컬+센서 동시 관측 적 인지 1(로컬 1·공유 0); HP 1 적 4체를 앞 화차가 전멸 → 뒤 화차 같은 틱 발사 0 | 테스트 "AC-05" 15건 |
| AC-06 | **PASS** | WP-001 회귀 전체 + fixture B 성능 계약 + 실제 공유 사격 | WP-001 회귀 135/135(wp001 모드, R-01 경계 포함) + WP-002 138 = **273/273**. 성능: 아래 표. network_combat: B8 전환 **12/12**, 장승 (22,28) 설치/제거 **12/12 성공·거절 0**, path_version **15 = 기대 15**, 위상 v16→v28, **공유전용 사격 123발**(첫 발 sim t=3.88s), 총 197발·처치 4,830, alive_min 1000 | `wp-002/tests/test_report.txt`; `wp-002/perf/perf_network_move_1000_release.json`, `perf_network_combat_1000_release.json`, `*.memory.json` |
| AC-07 | **PASS** | 새 시설 배치·단절 상태 읽기·조작 | 봉수대를 골목에 설치해도 경로 버전 불변·통행 유지; 센서 겹침 거절, 비활성 후에도 겹침 거절(점유 유지), 지형·경계·적 점유 거절, 미리보기 일치, 제거 후 재설치, 알 수 없는 id 거절. 화면: 간선·부착선·탐지/로컬/연결 반경·그룹 태그·비활성 회색, 커서 패널(부착·그룹·로컬/공유·표적 출처·대기 이유), 키 3/4/T와 안내 줄 | 테스트 "AC-07" 17건; 캡처 5장(HUD·패널·반경 표시) |
| AC-08 | **PASS** | 새 체크아웃 재현, 초기화 시 이전 망 제거, 오래된 산출물 차단 | README·이 절·`scripts/verify.*`(4b/6b, 산출물 선삭제, 계약 검사). 결정성: 같은 시드·명령(B8 비활성/활성)에서 그룹·화차별 인지 id·발사·공유전용·처치 재현, 다른 시드 불일치. 초기화: 시설 16 복원·적 0·발사 0·인지 0·활성 복원 | 테스트 "same seed…" 12건; 이 문서의 SHA·설정·fixture |

WP-002 계약과 다른 점(정직 기록): fixture A 4단계 "로컬 사격"은 지정 H(46,29)로는 기하상 불가능해 보조 화차 H2(48,41)로 입증했다(P-010, 아래 "미해결 문제"). 그 외 계약 수치·정책은 그대로 적용했다.

## 성능

- OS / CPU / GPU / RAM / 해상도 / 빌드 설정: 위 실행 환경. `exported release`, x86_64, pck 내장, gl_compatibility, 창 1920×1080, vsync 0.
- 시나리오 / 동시 생존 적 수 / 준비·측정 시간: fixture B(화차 4·봉수대 8·센서 4, 적 생성 전 설치, 시드 20260913), `benchmark_hold_alive` 로 매 틱 끝 1,000 보충, 10초 준비 + 60초 측정. 스크립트 실행 중 Esc 외 입력 무시.

| 회차 | 시나리오 | 프레임 / 초 | 생존 min / avg / max | 부하 유지 | 평균 FPS | 프레임 ms p50 / **p95** / p99 / max | sim step ms avg / p95 / max | 이벤트 | 워킹셋 MB 시작→종료 (최대) | 종료 |
|---|---|---|---|---|---|---|---|---|---|---|
| **2 (채택)** | network_move | 15,671 / 60.00 | **1000 / 1000.0 / 1000** | true | **261.2** | 2.79 / **10.03** / 11.74 / 16.89 | 2.23 / 2.49 / 2.83 | 시설 16 활성 16, 그룹 [5], 간선 8, pv 3=기대 3 | 172.0→176.7 (176.8) | 0 |
| **2 (채택)** | network_combat | 15,281 / 60.00 | **1000 / 1000.0 / 1000** | true | **254.7** | 2.79 / **10.12** / 11.73 / 18.18 | 3.99 / 7.64 / 8.72 | B8 전환 12/12, 장승 12/12(거절 0), pv 15=기대 15, 위상 v16→v28, 197발 중 공유전용 123, 처치 4,830 | 172.8→177.7 (177.8) | 0 |
| 1 (참고) | network_move | 15,621 / 60.00 | 1000 / 1000.0 / 1000 | true | 260.3 | 2.81 / 10.05 / 11.74 / 17.58 | 2.21 / 2.53 / 2.67 | pv 3, 기대값 필드가 2로 잘못 기록됨(장부 오류) | 168.3→170.7 | 0 |
| 1 (참고) | network_combat | 15,473 / 60.00 | 1000 / 1000.0 / 1000 | true | 257.9 | 2.78 / 10.08 / 12.00 / 20.80 | 4.01 / 8.04 / 9.85 | 12/12, 12/12, 공유전용 123, pv 15 (기대 14로 잘못 기록) | — | 0 |

- 평균 FPS / p95 / 메모리: 예산 평균 ≥60 → **261.2 / 254.7 (통과)**, p95 ≤25 ms → **10.03 / 10.12 ms (통과)**, 매 프레임 alive ≥1000 → `alive_raw` 전 원소 1000 (통과). 60초 워킹셋 증가 ≤5 MB.
- 원시 검산: `frame_us_raw` 길이 = frames, 모든 간격 > 0, 합계 60.00s, 재계산 FPS 261.2 / 254.7, p95 10.032 / 10.119 ms — 저장값과 일치. `alive_raw` 길이 = frames.
- 회차 1은 `path_version_expected`를 상수 2로 계산한 장부 오류(perf 모드가 reset()을 한 번 더 호출해 시작값이 3)로 채택하지 않고 `*_run1_pv_bookkeeping.json`으로 보관했다. 시뮬레이션·계약 수치 자체는 회차 2와 동일 경향이다. 수정은 측정 시작 시점의 path_version을 기록해 기대값을 계산하는 것뿐이며 구현 커밋 `efa53bb`에 포함됐다.
- WP-001 대비: 같은 장비에서 WP-001 combat 420.7 FPS / p95 7.25 ms → WP-002 network_combat 254.7 / 10.12. sim step 평균 2.37 → 3.99 ms: 센서 4×1000 + 화차 4×1000 거리 검사와 화차별 인지 집합 재구성 비용이다. 예산 내이나 5,000개체 확장 시 공간 분할이 필요할 것으로 본다(미측정).

## 실제 화면 확인

`--capture=wp002_a`가 지정 시각에 뷰포트 PNG와 상태 JSON을 남긴다(1배속, 정지 표적). 성능 실행(이동 1,000체)과 구분된다.

| 캡처 | 관측 |
|---|---|
| `wp002_a1_disconnected_no_fire_t2.png` | B 비활성(회색), S·H 부착 없음(그룹 -), H 인지 0/0, 발사 0, HUD "공유전용 사격 0", 적 1체가 Z0에 정지 |
| `wp002_a2_connected_shared_fire_t2.5.png` | B 활성(불꽃), H·S 부착선(점선)과 그룹 2 태그, 센서 140 반경 안 적, H 로컬 0/공유 1, Z0 표적선·폭발 링, HUD "H 화차→Z0 1발", "공유전용 사격 1" |
| `wp002_a3_disconnected_again_no_stale_fire_t5.png` | B 비활성, 그룹 [], H 발사 1 유지(준비 완료 2.5초 경과에도 추가 발사 없음), 대기 "표적 없음" |
| `wp002_a4_local_fire_while_disconnected_t5.5.png` | 망 없음(그룹 []), H2(동편 골목) 로컬 1/공유 0, Z1 표적선, H2 1발·H 1발 유지 |
| `wp002_a5_reconnected_reacquired_t7.png` | B 활성, 그룹 [2]에 H·H2·S 부착, H 2발·처치 1, H2 2발·처치 1, 공유전용 사격 2 |

인터랙티브 확인(캡처 없음): fixture B에서 3/4로 봉수대·혼천의 설치, T로 B8 비활성 시 S3 부착 해제·중영 화차 공유 인지 0으로 전환, 커서 패널에 부착·그룹·출처·대기 이유 표시.

## 미해결 문제와 설계 변경 제안

1. **P-010 fixture A 로컬 사격 기하(GPT 판단 요청)** — H(46,29)=(940,600)과 가장 가까운 후보 영역 원 가장자리(Z0/Z1, y≥705)까지 112px라 로컬 100px 안이면서 후보 영역 안인 적이 존재할 수 없다. 계약 4단계는 보조 화차 H2(48,41)=(980,840)로 입증했다(Z1 90px 로컬, fixture 적 120px 비로컬). 대안: 현행 수용 / 광장 남단 후보 영역 추가(fixture B "8개 영역"·WP-001 모드 보존에 영향) / fixture A의 H 위치 변경.
2. **성능 여유 감소** — 봉수망 탐지로 sim step이 WP-001 대비 약 1.6~1.8ms 증가. 예산 내이나 시설·적 수가 늘면 센서·화차 탐지에 공간 해시가 필요하다(측정 후 결정, CLAUDE.md 원칙 3).
3. **프레임 시간 이봉 분포** — p50 2.8 vs p95 10 ms. WP-001과 같은 미측정 항목(HUD 재배치 의심).
4. **벤치마크 처치 수(P-011)** — network_combat의 4,830 처치·123 공유전용 사격은 즉시 보충 부하에서 얻은 값으로 밸런스 자료가 아니다.
5. **캡처 시나리오의 path_version 3** — 캡처 설정이 reset()을 한 번 더 호출해 시작값이 3이다(장부 표기, 동작 무관).
6. **비활성의 의미** — 시설 HP·파괴는 범위 밖이라 T 키 디버그 전환으로 대체했다(D-014). 비활성 센서·봉수대는 점유만 유지한다.
7. **P-007 홀드 대기**는 그대로 남는다. network_combat의 장승 (22,28)은 평시 미사용 골목(P-008)이라 거절 0이었다.

## 다음 WP 영향 (WP-003)

- 재사용: `set_active()`가 구역 붕괴 시 외곽 시설 비활성화의 기본 수단이 된다(점유 유지·기능 중단). `BongsuNetwork.rebuild()`는 시설 변경 시 즉시 그룹을 갱신하므로 붕괴 후 내곽 망만 남는 상태를 바로 관측할 수 있다. 화차 회수·재배치는 `remove_structure` + `place_structure`로 표현 가능(비용 없음).
- 인터페이스: 시설은 `Placement.Structure` 하나에 `kind/active/attached_to/group_id`가 있다. WP-003의 구역 소속은 별도 필드(또는 앵커 기반 판정)를 추가하면 된다. 목표 변경(외곽 거점→핵심 시설)은 `PathNetwork.set_goal` + `rebuild()`로 가능하지만 현재 목표는 하나뿐이라 "외곽 거점 HP" 개념은 새로 필요하다.
- 주의: (1) `path_version`은 장승 변경에만, `topology_version`은 망 변경에만 증가 — WP-003의 붕괴 이벤트는 둘 다 바꿀 수 있으므로 기대값 계산에 시작값을 기록한다(이번 R-02 교훈). (2) 탐지는 틱에서만 갱신되므로 명령 직후 스냅샷의 인지 수는 다음 스텝 후에 읽는다. (3) 세대 id는 16비트 슬롯 한계(65,536)를 가정한다.

## PR

- Draft PR: https://github.com/darkrunar/hanyang-defense/pull/2 · 결과·증거 커밋 `8471809`

## GPT Review

- 검토일 / 검토한 구현 커밋: (PENDING) / `efa53bb`
- 최종 판정: **PENDING**
- 기준별 검토 결과: (PENDING)
- 범위 준수 / 기획 일치 / 증거 충분성: (PENDING)
- 보완 요청 또는 다음 WP 준비 사항: (PENDING) — 특히 P-010(fixture A 로컬 사격 기하)에 대한 판단을 요청한다.

이 문서는 구현·테스트 결과 기록이며, DONE 전환은 모든 필수 AC 충족과 GPT PASS 이후에만 한다.
