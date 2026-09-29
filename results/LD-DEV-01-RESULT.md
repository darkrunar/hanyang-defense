# LD-DEV-01 Result — 지도 신뢰성

- 작성일: 2026-09-29
- 작업 / 상태: [레벨 개발 계획](../docs/LEVEL_DEVELOPMENT_PLAN.md) LD-DEV-01 (AC-M01~05) / **REVIEW — GPT Review PENDING**. 계획 ID이며 새 WP 번호·READY 선언이 아니다. 착수는 2026-09-29 사용자 지시("LD-DEV-01 진행").
- 기준 커밋: `ddabd04` (wp/005-art-sample, "publish stage map editor baseline and level development handoff"). 착수 시 로컬 미커밋 변경 없음(clean). 기준에서 맵 88건·전체 1,456/0 재현.
- 검증한 구현 커밋: `c429855`(구현) → `c641ce9`·`be96f71`·`e70995f`·`a231bd3`(증거 도구·에디터 표시 보완) → `23b8449`(uid 파일만). 증거는 `a231bd3`에서 생성했고 `23b8449`는 스크립트 내용 변경 없음. 결과·증거 커밋은 이 문서의 커밋(자기참조 회피).
- 브랜치: `wp/ld-dev-01-map-reliability` (base `wp/005-art-sample`, stacked Draft PR)
- 실행 환경: Godot 4.7.stable.official.5b4e0cb0f · Windows 11 Home 10.0.26200 · AMD Ryzen 5 7600 · NVIDIA GeForce RTX 4070 SUPER(+ Parsec 가상 어댑터) · 63.2 GB · 에디터 창 1920×1080 · Python 3.13 + Pillow 12.2(GIF 변환)

이번 결과는 **에디터 경로 모델과 지도 데이터 검사**다. 실제 전투(사격·피해·승패)는 실행하지 않았고 범위도 아니다(LD-DEV-02). 이미지와 영상은 모두 에디터 **경로 미리보기**이며 화면 상단에 "경로 미리보기 · 실제 전투 아님"을 표시했다.

## 구현 결과

| 파일 | 목적 |
|---|---|
| `game/maps/stage_map_definition.gd` | M01 `goal_rejection()`·`set_goal()` 거절 코드(벽을 지우지 않음) / M02 `wall_leak_cells()`·`misplaced_gates()`·`goal_reachable_from_entries(open/closed)`·`route_order_problem()` / M03 `spawn_candidate_cells()`·`spawn_candidate_report()` / 결정적 `nearest_entry` 동률 처리 / 형식 v4 `spawn_seed` / M05 `parse_dictionary()`·`load_json_result()` 로드 정책, `to_json_text()` |
| `game/maps/stages/stage_003_r01.json`, `stage_003_r01_control.json` (신규) | M04 fixture: Stage003 수정안(장애물 x28~35,y29~30 하나)과 무지형 대조군. 같은 명시 seed |
| `game/tools/map_editor.gd` | 목표 거절 표시(상태 문구+지도 표시), 생성 후보 전체 표시(흰 원=유효, 빨간 X=거절), 실패 항목 우선 표시, R-01 수정안/대조군 버튼과 회색 대조 동선, 불러오기 거절 사유, 상태 문구에 가상 경로만 표시, 캡처 인자 `--map/--compare/--goal/--preview/--capture` |
| `game/tools/ld_dev_01_compare.gd` (신규) | M04 비교 JSON, fixture 재생성 `--write-fixtures`, 캡처 입력 생성 `--write-capture-inputs` |
| `game/tools/map_contract_probe.gd` (신규) | 기준 API만 쓰는 동작 조사. 기준/수정 커밋에서 같은 스크립트를 돌려 전후 비교 |
| `tests/test_ld_dev_01_map_reliability.gd` (신규), `tests/test_stage_map_editor.gd` | AC-M01~05 회귀 161건(기존 맵 suite에 연결 → focused·전체 러너 모두 실행) |
| `scripts/capture_ld_dev_01.ps1`, `scripts/frames_to_gif.py` (신규) | 증거 일괄 생성(깨끗한 트리 강제, 기준 worktree probe, 테스트, 비교, 캡처 9장, 미리보기 영상 2개, 경로 치환, manifest) |

`game/core/`는 변경 없음(`git diff ddabd04..HEAD -- game/core` 비어 있음). 전투·경로·망 런타임 동작은 그대로다.

## 실행·재현 절차

```powershell
godot --headless --path . --script res://tests/run_stage_map_tests.gd      # 맵 suite 249건
godot --headless --path . --script res://tests/run_tests.gd                # 전체 1,617건
godot --headless --path . --script res://game/tools/map_contract_probe.gd  # 동작 조사
godot --headless --path . --script res://game/tools/ld_dev_01_compare.gd -- --out=user://ld_dev_01 --sha=<commit>
.\scripts\capture_ld_dev_01.ps1                                            # 증거 전체 (깨끗한 트리 필요)
godot --path . res://game/tools/map_editor.tscn                            # 에디터: "Stage003 R-01 수정안" 버튼
```

시드: 두 fixture 모두 `spawn_seed = 2003935061` (= Stage001의 기존 파생 seed `"stage_001".hash() ^ 20260924`). 따라서 stage_id가 달라도 12개 표본 좌표가 Stage001과 같다: (33,39) (32,38) (31,40) (33,40) (29,40) (30,41) (31,43) (30,40) (32,40) (33,38) (29,38) (31,41).

## 기준 동작 재현 (수정 전 → 후)

같은 `map_contract_probe.gd`를 기준 `ddabd04`(임시 worktree)와 `a231bd3`에서 실행했다. 전체 출력: [probe_before.txt](evidence/level-development/LD-DEV-01/20260929-a231bd3/probe_before.txt) / [probe_after.txt](evidence/level-development/LD-DEV-01/20260929-a231bd3/probe_after.txt).

| 항목 | 기준 `ddabd04` | 수정 후 |
|---|---|---|
| 목표 성 밖 (31,30) | validate ok=**true** (R-02 재현) | ok=false, 오류 4 |
| 목표 성문 (31,25) | ok=**true** | ok=false |
| `set_goal` 성벽 (24,17) | 반환 없음, 벽 **지워짐**(1→0), 목표 이동 | 반환 `wall`, 벽 유지, 목표 (31,17) 유지 |
| 성문 셀을 필드 (31,33)에 추가 | ok=**true** | ok=false (성문 위치·동선 순서) |
| JSON 파일 왕복 wave_count | 7 → **7.0**(float), 재저장 파일 불일치(16815≠16817 B) | 7(int), 재저장 **바이트 동일** |
| cells 10개짜리 파일 | 경고 없이 **빈 지도** 반환 | 거절(null)과 사유 |
| 기존 지형 템플릿 경로 변화 (R-01) | 0/12 | 0/12 (템플릿 보존, 기준선으로 기록) |
| 수정안 장애물 경로 변화 | 12/12 | 12/12 |

## Acceptance Criteria

| AC | 판정 | 기대 결과 | 실제 결과 | 증거 |
|---|---|---|---|---|
| AC-M01 목표 위치 | **PASS** | 외부 (31,30)·성벽·성문·범위 밖 거절, 내부 (31,17) 허용, 자동 이동/벽 삭제 없음 | 거절 코드 8종 사례(외부·성벽·성벽 모서리·성문 2셀·진입점·범위 밖 x/y·필드) 모두 거절, 내부 4모서리와 (31,17) 허용. 거절 4회 후 목표 (31,17)·cells 불변. 성 정의 없음은 `no_castle`로 거절. 에디터 목표 도구도 같은 거절과 사유 표시 | tests_map.txt "AC-M01 …" 3개 case, editor_04/05/06 캡처, probe 전후 |
| AC-M02 성벽·성문 | **PASS** | 닫으면 도달 불가, 열면 도달, 문 외 구멍 탐지, 외곽 진입→문→목표 순서 | 성문 폐쇄 시 목표 도달 불가·열면 도달(에디터 flood와 core `PathNetwork` 일치: 폐쇄 시 5/5 진입점 차단). 구멍 4곳((24,17),(27,25),(39,12),(30,10))과 성벽 위 진입점을 누수 셀로 정확히 지목. 필드 성문·모서리 성문 거절. 12개 표본 모두 순서 검사 통과, 문 이전 성 밖·이후 성 안 확인. 문 통과 후 외부 목표로 되나가는 지도 `left_castle_after_gate` 거절. 끊긴 경로·진입점 누락 경로 거절 | tests_map.txt "AC-M02 …" 3개 case, editor_08 캡처 |
| AC-M03 생성 범위 | **PASS** | 정수 셀 후보 명시, 화면 안/벽/도달 불가 검출, 전수 검사와 12개 표본 구분 | 후보 모델 = 반올림 셀의 닫힌 단위 상자가 반경 안에 닿는 셀. 반경 0.5/1/3 → 5/9/45셀. 400 seed×12 = 4,800개 생성점이 모두 모델 안이고 45셀 전부 실제로 생성됨(모델이 정확). 중심 (31,37): 화면 안 셀·화면 안 벽 셀을 사유별로 집계, **12개 표본은 PASS인데 전수 검사는 FAIL**(생성기가 화면 안 셀을 건너뛰기 때문). 경계: 중심 (31,39) 45/45 유효, (31,38)은 y35 행 화면 안. 진입점 (33,35) 봉쇄 시 그 진입점을 쓰는 후보만 도달 불가 | tests_map.txt "AC-M03 …" 2개 case, editor_07 캡처(33/45 유효) |
| AC-M04 지형 효과 | **PASS** (G1 최소선) | 수정안과 무지형 대조군에 같은 생성 좌표, 12개 중 1개 이상 경로 변화, 전체 유효 후보 접근 유지 | 같은 12개 좌표 확인. **12/12 경로 변화**, 길이 +4~+8칸(평균 +6.5), 우회 좌 7·우 5. 유효 후보 45/45(대조군·수정안 모두). 전체 45개 후보도 45/45 변화. core `PathNetwork`도 5/5 진입점 경로가 바뀌고 모두 성문 경유 도달. 장애물은 경계·성벽과 닿지 않음. 기존 지형 템플릿은 같은 좌표로 0/12(R-01 기준선) | [stage003_r01_route_compare.json](evidence/level-development/LD-DEV-01/20260929-a231bd3/stage003_r01_route_compare.json), editor_02(전)/03(후) 캡처, preview_*.gif, tests_map.txt "AC-M04" |
| AC-M05 저장 재현 | **PASS** | 실제 JSON 파일 저장→로드 후 지도·설정·seed·검사·경로 동등, 정수 로드 정책 명시 | 실제 파일(`user://`)로 저장→로드: 전체 필드 사전 동일, wave_count int, spawn_rate 7.3·test_duration 45.25 정밀도 유지, seed·반경·cells 동일, 표본·검사 목록·미리보기 경로·전수 후보 보고 동일, 재저장 바이트 동일(칠한 순서가 다른 진입점 포함). 거절 11종(소수 정수, cells 길이·값·소수, 목록 불일치 2, 미래 형식, map_type, 소수 좌표, 문자열 seed, cells 누락)과 잘린 JSON·없는 파일 거절. v3 파일(spawn_seed 없음)은 기존 표본 그대로 로드 | tests_map.txt "AC-M05 …" 2개 case, editor_09 캡처, probe 전후 |
| Stage001 정상 fixture·기존 회귀 | **PASS** | 기존 맵·전체 회귀 유지 | 기존 맵 88건 그대로 통과(기대값 변경 없음), 맵 suite 249/0, 전체 1,617/0(기준 1,456 + 신규 161) | tests_map.txt, tests_full.txt |

### 로드 정책 (AC-M05에서 명시한 것)

- Godot JSON 파서는 모든 숫자를 float로 돌려준다(수정 후 테스트가 이를 확인). 정수 필드 — `format_version`, `width`, `height`, `cells[]`, 좌표(`spawn_center`, `goal`, `gates`, `entries`), `spawn_sample_count`, `spawn_seed`, `castle_rect`, `tuning.wave_count` — 는 **정수값이어야 하고 int로 복원**한다. 소수(2.5 등)는 잘라내지 않고 오류다.
- 실수 필드 — `spawn_radius_cells`, `tuning.spawn_rate`, `tuning.test_duration` — 는 숫자면 허용한다. 저장은 `full_precision`로 값이 정확히 돌아온다. 그 밖의 tuning 키는 읽은 그대로 보존한다.
- 깨진 파일은 사유 목록과 함께 거절하고 지도를 반환하지 않는다. 에디터는 현재 화면 지도를 유지한다(템플릿으로 조용히 대체하지 않음).
- `gates`/`entries` 목록은 cells에서 다시 만들고, 파일의 목록이 cells와 다르면 오류다. 저장 순서는 행 우선(정규 순서)이다.
- 형식 v4는 `spawn_seed`(음수=stage_id 파생, v1~v3 동작)를 추가한다. 이 빌드보다 새 형식은 거절한다.

## 성능

비해당 / 재측정 NOT RUN. `game/core/` 경로·전투·망 코드를 바꾸지 않았고 게임 실행 경로에 새 계산이 없다. 추가 계산(후보 전수 검사, 누수 flood)은 에디터와 테스트의 `validate()`에서만 돈다. 계획의 "경로/전투/망 변경 시 1,000체 재측정" 조건에 해당하지 않는다. 전투 연결(LD-DEV-02)에서 지도 로딩이 게임 경로에 들어가면 그때 측정한다.

## 실제 화면 확인

실제 에디터 창(1920×1080, windowed)에서 캡처했다. 증거 폴더: `results/evidence/level-development/LD-DEV-01/20260929-a231bd3/` ([manifest.json](evidence/level-development/LD-DEV-01/20260929-a231bd3/manifest.json)에 파일별 sha256).

| 파일 | 보이는 것 |
|---|---|
| editor_01_control_flat.png | 대조군(무지형): 12개 표본 경로가 성문 아래 직선으로 모임, 후보 45/45 |
| editor_02_r01_before_legacy_terrain.png | 기존 지형 템플릿(R-01 이전): 측면 장애물이 경로와 만나지 않아 파란 경로가 회색 대조 경로와 겹침 |
| editor_03_r01_after_revised.png | 수정안: 장애물 좌우로 우회하는 파란 경로, 회색 직선 대조 경로와 분리 |
| editor_04/05/06_goal_refused_*.png | 목표 도구로 (31,30)·(24,17)·(31,25) 클릭 → "목표 거절" 표시와 사유, 목표 (31,17) 유지 |
| editor_07_spawn_candidates_on_screen.png | 중심 (31,37): 화면 안 후보 빨간 X, "생성 후보 전수 33/45", FAIL 사유 |
| editor_08_wall_hole_24_17.png | 성벽 구멍: "성벽 폐쇄"·"성문 외 진입 차단" FAIL, 구멍 좌표 (24,17) |
| editor_09_broken_file_refused.png | wave_count 2.5 파일 → "불러오기 거절 … tuning.wave_count: 정수가 아닙니다 (2.5)", 화면 지도 유지 |
| preview_r01_before_legacy_terrain.gif / preview_r01_after_revised.gif | 경로 미리보기 애니메이션 6초(20 fps 고정 120프레임, GIF 0.5배·10 fps). 빨간 점은 미리보기 점이며 전투 적이 아님 |

## 미해결 문제와 설계 변경 제안

1. **P-022 (GPT 판단 요청) — 미리보기 경로와 전투 경로의 모양 차이.** 에디터 미리보기는 성문 통과를 강제하는 4방향 BFS다. 전투의 `PathNetwork`는 8방향(모서리 절단 없음) 흐름장이고 성문 통과를 강제하지 않는다. 도달 가능 여부는 같다. 8방향 이동은 두 직교 이웃이 열려 있어야 하므로 직교 두 걸음으로 바꿀 수 있고, 테스트도 성문 개폐 결과가 일치함을 확인했다. 그러나 경로 모양은 다르다. 진입점 (31,35)에서 에디터 수정안 경로는 27칸, core 흐름장은 21셀(대각 포함)이다. 좌우 선택도 동률 처리에 따라 달라질 수 있다. 구멍 있는 지도에서는 에디터가 여전히 성문으로 그리지만 core는 구멍을 쓴다. 이번 누수 검사로 그런 지도는 저장 전에 FAIL로 막힌다. 제안: LD-DEV-02에서 미리보기를 core 흐름장 경로로 바꾸거나 둘을 함께 그린다.
2. **집결 셀은 바뀌지 않았다.** 대조군·수정안 모두 12개 경로가 성문 앞 (31,26)을 거쳐 성문 (31,25)로 들어간다. 수정안이 바꾼 것은 접근 방향(좌 7·우 5)과 길이(+4~8칸, 노출 시간 증가)다. LD-06의 "접근 방향·노출 시간·집결 위치 중 하나"에서 앞의 두 항목에 해당한다. 사격 기회가 실제로 늘어나는지는 LD-DEV-05 판정이다(이번 PASS를 경험 판정으로 쓰지 않음).
3. **기존 `terrain_template()`은 그대로 두었다.** "지형맵 새로 만들기" 버튼은 여전히 R-01 이전 템플릿이다. 수정안은 별도 파일이다(단계별 설계의 "수정안은 별도 파일로 비교" 지시). 템플릿을 수정안으로 바꿀지는 GPT가 결정한다.
4. **fixture는 release 빌드에 포함되지 않는다.** `export_presets.cfg` include_filter가 WP-005 에셋만 포함한다. LD-DEV-02에서 release로 지도를 불러오려면 `game/maps/stages/*.json`을 포함해야 한다.
5. 시설 후보 A=(25,29)·B=(30,26)은 수정안에서 2×2 점유 칸이 모두 빈 필드다(비교 JSON `facility_candidates`). 타깃 존·사거리·발사 검사는 LD-DEV-05 범위라 하지 않았다.
6. 증거 스크립트는 7단계를 모두 마쳤고 각 단계 종료 코드를 검사했다. 다만 스크립트 종료 뒤 PowerShell 세션이 exit 255를 보고했고 원인은 분리하지 않았다(임시 폴더·worktree 정리까지 완료 확인).

## 다음 작업 영향

- LD-DEV-02가 쓸 인터페이스: `StageMap.load_json_result(path)` → `{ok, data, errors}`(오류 파일 표시 요건과 맞음), `build_grid()`/`build_path()`(기존), `goal_rejection()`, `wall_leak_cells()`, `spawn_candidate_cells()`(전투 생성기가 같은 모델을 쓰면 전수 검사가 그대로 유효), `effective_spawn_seed()`.
- 전투 생성에 에디터의 `generated_spawn_points()`를 재사용하면 화면 안 후보를 건너뛰는 동작도 따라온다. 전수 검사는 이미 그런 지도를 FAIL로 막는다.
- Stage001~004 제작 시 A/B는 명시 `spawn_seed`로 좌표를 고정한다(stage_id 파생 seed에 의존하지 않음).

## 개발 10계명 적용 기록

- 대상 플레이어 / 기대 경험: 레벨 제작자(GPT·사용자)가 저장 전에 "적이 화면 밖에서 와서 성문을 지나 성 안 목표로 간다"가 전 범위에서 성립함을 확인한다. 플레이어 경험 자체는 이번 범위 밖이다.
- 선택한 T-ID: T-04 즉시 피드백(에디터 거절 사유), T-10 설정 재현(seed·파일 왕복). 비해당: T-01/02/03/05/06/07/08/09 — 전투·보상·압박·재도전이 없는 지도 도구 작업이다.

| 원칙 | 적용한 변경 | 확인 조건·증거 | 판정 |
|---|---|---|---|
| T-04 | 목표 거절을 조용히 무시하지 않고 셀 표시와 사유 문구로 보여 줌. 실패 항목을 목록 맨 위에 둠. 불러오기 거절 사유 표시 | editor_04~09, 에디터 테스트 | 충족(에디터 기능), 사용자 체감 미평가 |
| T-10 | seed 파일 저장, 정수 타입 복원, 재저장 바이트 동일, fixture 규칙과 파일 일치 검사 | AC-M05 테스트, probe 전후 | 충족 |

- 관찰 사실 → 영향 → 개선 → 재검증: 기준 에디터는 성 밖 목표를 허용하고 벽을 지워 목표를 뒀다 → 잘못된 지도가 PASS로 저장됨 → 거절+사유+지도 불변 → probe와 테스트로 재검증.
- core 판정 불변: `game/core` 변경 없음. 수치 변경 없음. 밸런스 값 미변경.
- 후속 우선순위: ① P-022 미리보기/전투 경로 일치(LD-DEV-02) ② release에 지도 포함 ③ 템플릿 교체 여부(GPT).

## GPT Review

- 검토일 / 검토한 구현 커밋:
- 최종 판정: PENDING
- 기준별 검토 결과:
- 범위 준수 / 기획 일치 / 증거 충분성:
- 보완 요청 또는 다음 작업 준비 사항:
