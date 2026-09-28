# WP-005 Result

최신 보완: PR #12, 통합 구현 `133f39e`(상위 `274ad7a` 포함). 전용 비활성 생성 그림과 적 프레임 보정, 실제 리소스 F1/F2/F4 비교를 유지하면서 기본 sample 실행·희소 바닥·1000체 캡처·추가 테스트를 병합했다. 이하 회차별 기록은 해당 커밋의 증거이며 최신 결과는 문서 마지막 통합 검증 절을 따른다.

- 작성일: 2026-09-20
- WP / 상태: WP-005 그래픽 기준 및 광화문 앞 샘플 적용 / **IN_PROGRESS** (회차 1 파이프라인 → 회차 2 시설 시안 → 회차 3 PR #11 부분 통합·검수 REVISE 반영 `33e2f8d`. 17/35 상태 파일, GPT 판정 REVISE 유지, 사용자 스타일 확인(AC-08) 전 → REVIEW 아님)
- 기준 커밋: main `51d89ed`(WP-004 병합) + 계획 브랜치 `03f78d4`("docs(art): prepare WP-005 …", READY v1.0, D-048). 착수 브랜치 `wp/005-art-sample`은 `03f78d4`에서 분기.
- 검증한 구현 커밋: **`0f2fc6c`** ("feat(wp-005): art sample pipeline …") → `b262ce0`(uid 파일만) → `6e6c07c`(verify.ps1 보간 수정·가이드; 게임 스크립트는 `0f2fc6c`와 동일). 결과·증거 커밋: 이 문서의 커밋(별도 문서 커밋으로 자기참조 회피).
- 브랜치: `wp/005-art-sample` · PR: Draft PR #8: https://github.com/darkrunar/hanyang-defense/pull/8 (Draft, 병합은 사용자 지시로만)
- 실행 환경 / 엔진·버전: Godot 4.7.stable.official.5b4e0cb0f (GDScript, 2D, gl_compatibility) · Windows 11 Home 10.0.26200 · AMD Ryzen 5 7600 · NVIDIA GeForce RTX 4070 SUPER · 63.2 GB · 1920×1080 창(캡처는 1280×720도) · vsync off · Parsec 가상 디스플레이 어댑터 공존. 이미지 도구: Python 3.13 + Pillow 12.2, Godot Image API. **이미지 생성 도구 없음**.

이 문서는 `results/RESULT_TEMPLATE.md` 양식을 따른다. WP-005는 리소스 제작(GPT + 이미지 도구)과 적용(Claude Code)이 나뉜 작업이며, 이 회차는 **적용 파이프라인과 검증 기반**을 만들고 도구 점검 결과에 따라 리소스 제작을 GPT 단계로 반환한 상태다. 아래 증거의 "sample" 화면·성능은 전부 **개발용 fixture**(도형 PNG, 에셋 아님)로 만든 것이며 AC-01/02/03/06/08과 AC-07의 최종 판정은 검수된 에셋이 들어온 뒤에만 가능하다.

## 구현 결과

| 파일 | 목적 |
|---|---|
| `game/scenes/art_set.gd` (신규) | 파일 계약 로더(D-049): `assets/art/wp005/<subdir>/<id>_<state>_v01.png`, N프레임 가로 스트립 자르기, 규격 검사, 기준점 규칙 + `pivots.json`, 적 아틀라스(4×3, 2px 여백), 누락/거절 목록과 SHA-256 보고. 없는 요소는 회색상자 유지 |
| `game/scenes/terrain_layer.gd` | 순수 타일 계획 `sample_plan`(바닥 4종 해시, 벽 접면 가장자리 0-3, 안쪽 모서리 4-7, 담장/지붕 모듈 반복, 광화문 문)을 샘플 구역 x30..65/y6..30에만 그림. 그리드·충돌 불변 |
| `game/scenes/overlay_layer.gd` | 시설/거점/표시 스프라이트를 core 상태(활성·그룹·muzzle·HP·붕괴·회수)로 선택, `L`/`--labels=off` 라벨 토글, sample에서는 blast 링 대신 fx |
| `game/scenes/fx_layer.gd` (신규) | 실제 이벤트 1:1 효과(발사·탄착·붕괴·적 피격·소멸), 시뮬레이션 시간 진행(메뉴에서 정지), 재시작 시 비움, PNG 없으면 절차적 도형 |
| `game/scenes/main.gd` | `--art=greybox\|sample`, `--art-dir=`, `--labels=`(scene 인자, Config 불변); 적 MultiMesh 1회 업로드 + custom data(흐름장 방향·2프레임) + 정점 셰이더 UV 선택; fx 공급(render_queue·render_events·collapse_count·HP 감소); 캡처 `wp005_<art>[_720]`(7장 + `state_log`/`art_log`), 캡처 스냅샷·성능 manifest에 `art_mode/art/fx/sprites_drawn/sample_tiles_drawn` |
| `game/core/enemy_sim.gd`, `game/core/hwacha.gd` | 렌더 장부만 추가(처치/피격 위치 256건 cap, 화차 중심). 시뮬레이션은 읽지 않음 |
| `game/tools/wp005_dev_fixture.gd` (신규) | 개발용 fixture PNG 35장을 `user://wp005_art_fixture`에 생성(에셋 아님, `assets/`·manifest 미포함) |
| `tests/test_art_sample.gd` (신규), `tests/run_tests.gd` | 로더/아틀라스/타일 계획/적 프레임/greybox==sample 6체크포인트/FX 계약/배선 |
| `scripts/verify.ps1 -Wp005`, `verify.sh` 4e, `perf_with_memory.ps1 -Art/-ArtDir` | fixture 생성 → 4캡처(모드×해상도) + greybox/sample 상태 동일·fx·타일 검사 → export → 모드별 collapse 성능 4회(D-027 계약) |
| `docs/art/source/WP005_REQUEST.md` (신규), `docs/DECISIONS.md` D-049, `backlog/WP-005.md`, `README.md`, `docs/GAME_GUIDE.md` | 도구 점검·제작 요청·파일 계약, 기술 결정, 상태 IN_PROGRESS, 실행 안내 |

## 실행·재현 절차

```bash
git clone https://github.com/darkrunar/hanyang-defense.git && cd hanyang-defense && git checkout wp/005-art-sample
```

| 단계 | 명령 | 산출물 |
|---|---|---|
| 자동 검증 | `godot --headless --path . --script res://tests/run_tests.gd -- --report=<abs>/results/evidence/wp-005/tests/test_report.txt` | **1,210 passed / 0 failed (69.5 s; 기존 1,106 + WP-005 스위트 6케이스)**, 종료 0 |
| 개발 fixture | `godot --headless --path . --script res://game/tools/wp005_dev_fixture.gd` | `user://wp005_art_fixture/` 35장 (에셋 아님) |
| 캡처 | `godot --path . --rendering-driver opengl3 -- --capture=wp005_sample --art=sample --art-dir=user://wp005_art_fixture --out-dir=<abs>/results/evidence/wp-005/captures` (`wp005_greybox`, `_720` 변형 동일) | PNG 7장 × 4 + `wp005_*_log.json` |
| 릴리스 빌드 | `godot --headless --path . --export-release "Windows Desktop Release" build_out/windows/hanyang_defense_wp001.exe` | exe |
| 성능 | `.\scripts\perf_with_memory.ps1 -Scenario collapse_move\|collapse_combat -Art greybox\|sample [-ArtDir user://wp005_art_fixture] -Warmup 10 -Measure 60 -Out results\evidence\wp-005\perf\perf_<sc>_<art>_1000_release.json` | 원시 배열·구간·이벤트·manifest(`art_mode/art/fx`)·exe 해시 |
| 일괄 | `.\scripts\verify.ps1 -Wp005` | 위 전부 + 계약 검사, 종료 0 |
| 실제 에셋 적용 시 | 파일을 `assets/art/wp005/<subdir>/`에 넣고 `--art=sample`(기본 디렉터리)로 같은 절차 | manifest `actual_path/sha256/status` 갱신 |

설정: 시드 20260913, 60 Hz, WP-003 계약값(HP 360/60, 18시설, 10존, 1,140체) 그대로. `--art`는 렌더링만 바꾼다.

## Acceptance Criteria

| AC | PASS / FAIL / NOT RUN | 기대 결과 | 실제 결과 | 증거 파일·로그·화면 |
|---|---|---|---|---|
| AC-01 | **NOT RUN** | 최소 묶음 제작·적용, manifest 추적 | 리소스 미제작(이 환경에 이미지 생성 도구 없음 → 11종 GPT 제작 단계 반환). 가져오기 계약·검증(규격/프레임/기준점/SHA)은 로더가 수행하며 fixture 35/35로 확인. manifest는 전부 PLANNED 그대로 | `docs/art/source/WP005_REQUEST.md`; 테스트 "ArtSet" |
| AC-02 | **NOT RUN** (파이프라인만) | 샘플 범위 길/벽·골목·내곽 가독, 20px 격자·점유 정합 | 타일 계획: 샘플 구역 open 652셀 전부 바닥, 벽 접면 가장자리 142, 담장 50·지붕 198, 문 1 — 그리드 불변. 실제 가독성 판정은 검수 타일 필요 | 테스트 "Terrain sample plan"; 캡처 `wp005_sample_a_dense_t15.png`(fixture) |
| AC-03 | **NOT RUN** (파이프라인만) | 시설 4종·작동/단절/비활성/회수 구분 | 상태→프레임 선택이 core 값에서만 나옴: 캡처 로그 `sprites_drawn`에 붕괴 전 `hwacha/idle 4, bongsu/pulse 8, sensor/active 4, outer_post/hit`, 붕괴 후 `hwacha/inactive 3, bongsu/disconnected 6, sensor/inactive 3, outer_post/collapsed, recovery_wait`, 재배치 후 `hwacha/idle 2`. 라벨 숨김(`--labels=off`/L) 제공. 실루엣 판정은 검수 에셋 필요 | `wp005_sample_log.json` sprites_drawn; 테스트 "Sample wiring" |
| AC-04 | **PASS** (fixture) | 효과가 실제 이벤트에 1회 대응, 메뉴/재시작 잔류 없음 | 발사 fx == 탄착 fx == 실제 볼리 수, 소멸 fx == 처치 수, 붕괴 fx 1회, 렌더 프레임만 돌리면 새 fx 0, PAUSED 120프레임 동안 fx 목록·시간 불변, 재시작 후 fx 0·카운터 초기화. 캡처(t45): fire 51 = impact 51, collapse 1, despawn 154 | 테스트 "AC-04"; `wp005_sample_log.json` `art_log t45` |
| AC-05 | **PASS** (파이프라인) | greybox/sample 전투 결과 동일, 기존 회귀 통과 | 같은 시드·명령의 두 scene: initial/t5/before·after collapse/after recovery/end 6곳에서 `full_state_json`·`state_hash` 동일, 결과 동일. 캡처 로그 `state_log` 4체크포인트 greybox==sample(1080p·720p), 종료 결과 동일. 전체 회귀 1,210 passed / 0 failed (69.5 s; 기존 1,106 + WP-005 스위트 6케이스) 종료 0 | 테스트 "AC-05 pipeline"; verify 4e; `tests/test_report.txt` |
| AC-06 | **NOT RUN** | 1,000체 가독성·두 해상도 겹침 없음 | fixture 화면만 존재(에셋 아님). GPT 시각 검수 대상 아님 | 캡처 4종(참고용) |
| AC-07 | **NOT RUN** (fixture 측정만) | sample 양쪽 시나리오 D-027 계약 | 같은 exe로 greybox/sample × collapse_move/combat 4회 측정, 전 프레임 alive ≥1000, 6 이벤트, 계약 검사 통과: collapse_move/greybox 178.0 FPS · p95 15.53 ms, collapse_combat/greybox 182.6 FPS · p95 15.43 ms, collapse_move/sample 155.1 FPS · p95 16.11 ms, collapse_combat/sample 166.1 FPS · p95 15.34 ms. **sample은 fixture 스프라이트(12×16)라 최종 에셋 측정이 아니다** | `results/evidence/wp-005/perf/perf_collapse_*_{greybox,sample}_1000_release.json` |
| AC-08 | **NOT RUN** | 사용자 스타일 확인·GPT 규격 승인 | 확인할 실제 샘플 없음 | — |

자동 검증 합계: **1,210 passed / 0 failed (69.5 s; 기존 1,106 + WP-005 스위트 6케이스)**, 종료 코드 0. `verify.ps1 -Wp005` 종료 0.

## 성능

OS / CPU / GPU / RAM / 해상도 / 빌드 설정: 위 실행 환경, 1920×1080, vsync off, release export(`fed1bcd35a7713ddf15312cbd34a528532b87c8acad30d9cc897668c5ed8f4c7`), manifest `implementation_sha` `6e6c07c`(= `6e6c07c`, 게임 스크립트 `0f2fc6c`).
시나리오 / 동시 생존 / 준비·측정: collapse_move·collapse_combat × greybox·sample(fixture), 1,000체 유지, 10 s + 60 s.

| 시나리오 · 모드 | 프레임 | 평균 FPS | p95 ms | alive min | 6 이벤트·구간·manifest | 워킹셋 MB(시작→끝) | 판정(D-027) |
|---|---:|---:|---:|---:|---|---|---|
| collapse_move · greybox | 10,678 | **178.0** | **15.53** | 1000 | 6 이벤트 · 구간 10678/10678 · manifest ok | 187.2→195.6 | PASS |
| collapse_combat · greybox | 10,956 | **182.6** | **15.43** | 1000 | 6 이벤트 · 구간 10956/10956 · manifest ok | 183.3→197.3 | PASS |
| collapse_move · sample(fixture) | 9,309 | **155.1** | **16.11** | 1000 | 6 이벤트 · 구간 9309/9309 · manifest ok | 197.9→210.1 | PASS |
| collapse_combat · sample(fixture) | 9,966 | **166.1** | **15.34** | 1000 | 6 이벤트 · 구간 9966/9966 · manifest ok | 186.9→192.8 | PASS |

greybox 대비 sample 차이는 fixture 기준이며 최종 에셋(크기·프레임 수)이 다르면 다시 측정한다. 원인 추정으로 판정하지 않는다.

## 실제 화면 확인

`results/evidence/wp-005/captures/`: `wp005_{greybox,sample}[_720]_{a..g}.png`(밀집 t15, 붕괴 t20.5, 배치 불가/가능 미리보기 t23/23.5, 재배치 t25.5, 내곽 사격 t45, 종료) + 로그. sample 화면은 fixture 도형이라 **스타일 판단 자료가 아니다**; 파이프라인이 무엇을 어디에 그리는지(샘플 구역 경계, 시설 상태 프레임, 적 방향/머리 위, 효과 위치·시간)를 확인하는 용도다. 확인한 것: 적 스프라이트 머리가 위(아틀라스·quad 방향 정상), 샘플 구역 밖은 회색상자 유지, 붕괴 후 외곽 시설 비활성 프레임·회수 대기 표시, 문·담장·지붕 모듈 위치.

## 미해결 문제와 설계 변경 제안

1. **리소스 제작 대기**: 11종 35파일 전부 GPT 제작 단계([WP005_REQUEST](../docs/art/source/WP005_REQUEST.md)). 파일이 오면 `assets/art/wp005/`에 넣고 manifest 갱신·캡처·회귀·성능 재실행 후 REVIEW로 전환한다.
2. 720p 축소는 비정수 배율이라 픽셀 크기 일정 보장이 없음(ART_GUIDE대로). 검수 에셋에서 흐림/실루엣 손실 검사가 필요하다.
3. 적 아틀라스는 6상태 프레임 크기가 같아야 한다(다르면 누락으로 보고, 회색 사각형 유지).
4. 샘플 구역 밖 지형은 회색상자다(부분 적용, WP-006 범위).
5. **greybox 성능 수치의 회차 간 하락**: 같은 기기에서 collapse_move greybox가 WP-003 회차 4 221.5 → WP-004 보완 200.4 → 이번 178.0 FPS(p95는 12.7 → 14.7 → 15.5 ms)로 내려왔다. 예산(≥60 / ≤25 ms)은 충족하지만 원인은 미확정이다. greybox 렌더 경로 코드는 WP-004와 같고(`_feed_fx`는 sample에서만), 이번 회차의 `_input` 장부와 `_check_run_end` 선행 호출은 프레임당 상수 비용이다. 통제 A/B(같은 exe를 재부팅 직후·백그라운드 프로세스 없이 반복 측정)는 NOT RUN이며, 다음 회차의 실제 에셋 성능 측정과 함께 수행할 것을 제안한다(P-item 아님, 측정 절차 제안).

## 다음 WP 영향

- 로더의 파일 계약(`ArtSet.CONTRACT`)에 ID/상태를 추가하면 WP-006 전체 전장 확장이 같은 경로를 쓴다. 타일 계획은 구역 rect만 바꾸면 된다.
- fx 레이어는 새 이벤트 종류를 `spawn(kind)`로 추가하되 반드시 core 장부와 1:1이어야 한다(AC-04 시험 패턴 재사용).

## PR

- Draft PR #8: https://github.com/darkrunar/hanyang-defense/pull/8 · 구현 `0f2fc6c` → `6e6c07c` (게임 스크립트 `0f2fc6c`) · 결과·증거 (문서 커밋)

## GPT Review

- 검토일 / 검토한 구현 커밋: (PENDING — 리소스 적용 후 REVIEW 전환 시 요청)
- 최종 판정: PENDING
- 기준별 검토 결과: (PENDING)
- 범위 준수 / 기획 일치 / 증거 충분성: (PENDING)
- 보완 요청 또는 다음 WP 준비 사항: (PENDING)

이 문서는 구현·테스트 결과 기록이며, DONE 전환은 모든 필수 AC 충족과 GPT PASS 이후에만 한다.

---

## GPT 시설 4종 파일럿 기록 (PR #10, 브랜치 `wp/005-facility-art-pilot`, `26b9d70` → `17f8c24`; 병합 `2572bb1`)

아래는 GPT 파일럿 브랜치의 결과 문서 원문이다(병합 시 보존). 파일럿 렌더러 `facility_art.gd`와 1254px 런타임 사본은 D-050에 따라 로더 경로로 대체되었고, 원본·제작 지시·검사 기록·증거(`results/evidence/wp-005/{greybox,sample}_*.png`, `render_checks.json`, `capture_pilot.gd`, 파일럿 `test_report.txt`)는 그대로 남아 있다.

## WP-005 시설 4종 시험 적용 결과

- 날짜: 2026-09-20. Status: IN_PROGRESS. GPT Review: PENDING.
- 계획 기준: 03f78d4 (WP-004 main 51d89ed 기반). 구현: 26b9d70.
- 사용자 “적용” 요청 범위: 생성된 시설 4종의 실제 전장 시험 적용. WP-005 전체 완료가 아님.

### 변경과 실행

화차·장승·봉수대·혼천의를 원본 PNG의 알파 영역에서 읽어 최대36×36px로 기존40×40px 점유 안에 그린다. 원본을 잘라 덮어쓰지 않으며 텍스처/영역은 캐시한다. 기본 일반 실행은 sample, 기존 perf/capture는 명시 옵션 없을 때 greybox다. 비활성 시설은 어둡게 표시하고 X를 추가한다. 점유·연결·회수는 기존 전투 상태를 그대로 읽는다.

```text
godot --path . -- --art=sample
godot --path . -- --art=greybox
godot --headless --path . --script res://tests/run_tests.gd -- --report=<absolute_report_path>
godot --path . --rendering-driver opengl3 --script res://results/evidence/wp-005/capture_pilot.gd
```

### 검증

- 전체 회귀: 1,106 PASS / 0 FAIL, 69.5초, 종료0. evidence/wp-005/test_report.txt.
- 실제 1080p/720p sample/greybox 캡처 생성 및 눈검수. render_checks.json의 렌더 전후 구조화 전투 상태 비교4건 모두 true. 이는 전체 F1/F2/F4 양쪽 모드 비교를 대체하지 않는다.
- 붕괴 후 비활성 시설 몸체 유지와 회수된 화차 제거 확인: sample_collapsed_720.png.
- Windows release export 성공, 120프레임 짧은 실행 종료0·stderr 없음. 실행파일은 별도 로컬 산출물이며 저장소에 커밋하지 않음.
- 1,000체 release 성능, 전체 샘플 사용자 확인: NOT RUN.

### 시각 검토와 남은 범위

시설 실루엣은 구분되며 발광보다 실제 연결선/라벨을 우선한다. 원본1254px를 작은 표시 영역에 그리므로 720p의 세부 묘사가 작다. 현재는 정적 시설 시험 적용이며 40px 원본 픽셀 정리·방향/프레임 통일·발사 애니메이션·전용 비활성/단절 리소스는 미완료다. 지형·적·거점·효과는 기존 도형이다. 회수 대기 아이콘도 기존 표시다. 큰 텍스처의 메모리 최적화와 시작 시 알파 영역 계산을 사전 메타데이터로 옮기는 작업은 후속 범위다.

### WP-005 AC 현황

AC-01~04, AC-06: 일부 작업만 수행되어 전체 기준 판정 NOT RUN. AC-05: 기존 회귀와 렌더 상태 비교는 PASS, 전체 F1/F2/F4 모드 비교 NOT RUN. AC-07/08: NOT RUN. 전체 WP PASS/DONE 또는 최종 스타일 승인으로 표시하지 않는다.

### 다음 작업

40px 크기에 맞춘 픽셀 보정과 시설 상태 프레임 제작, 지형/적/거점 최소 묶음 적용 후 전체 AC를 검증한다. 원본 제작 지시·도구는 docs/art/source/wp005/PROMPTS.md, 개별 상태는 ASSET_MANIFEST.csv에 기록했다.

---

### 2026-09-20 — 회차 2: 생성 시안 자동 보정 적용 (D-050)

- 커밋: 병합 `2572bb1` → 보정·적용 `06f6ecd`(변환 스크립트, 40×40 8파일, manifest, 기본 모드, 테스트, verify 4e 확장) → 결과·증거 (이 문서 커밋).
- 적용: `scripts/art_convert_wp005.py` — 알파 경계 크롭 → 긴 변 40px BOX 축소(배율 hwacha 0.0340, jangseung 0.0340, bongsu 0.0354, sensor 0.0339) → 24색 팔레트 → 이진 알파 → 바닥 중심 접지. 결과 `assets/art/wp005/facilities/`: hwacha idle/inactive, jangseung idle/inactive, bongsu connected/disconnected, sensor active/inactive (`inactive`/`disconnected`는 파생본). manifest 상태 `PILOT_DOWNSCALED_STATIC`, 파일별 SHA-256 기록. **완성 에셋 판정이 아니다**(ART_GUIDE).
- 기본 모드: `--art` 미지정 일반 실행 = sample, 스크립트 모드 = greybox(파일럿 브랜치 선택 수용).

| 항목 | 결과 |
|---|---|
| 테스트 | **1,259 passed / 0 failed (71.8 s)**, 종료 0 (새 케이스 "Reviewed assets": 8파일 40×40·pivot (20,20)·접지·SHA, 누락 27건 보고, 기본 모드, 240프레임 상태 동일) |
| 캡처 `wp005_assets`/`_720` (기본 디렉터리) | greybox 대비 4체크포인트 상태 동일, 로드 8/35 (누락 27), t15 시설 스프라이트 bongsu/connected 8, hwacha/idle 4, jangseung/idle 2, sensor/active 4, 붕괴 후 bongsu/connected 2, bongsu/disconnected 6, hwacha/idle 1, hwacha/inactive 3, jangseung/inactive 2, sensor/active 1, sensor/inactive 3 |
| 캡처 fixture/greybox | 파이프라인 검사 회차 1과 동일하게 통과 |
| 성능 | 회차 1과 같은 방식(sample = fixture)으로 재측정: collapse_move/greybox 195.2 FPS · p95 14.78 ms, collapse_combat/greybox 229.3 FPS · p95 13.19 ms, collapse_move/sample 163.0 FPS · p95 15.80 ms, collapse_combat/sample 193.7 FPS · p95 13.58 ms. 실제 에셋 성능(AC-07)은 적 스프라이트가 와야 의미가 있어 NOT RUN 유지 |
| AC-01 | **부분**: 시설 4종 정적 상태 8/…파일 적용, 원본→파일 추적·SHA·권리 검토 기록(AI 생성, 법적 클리어런스 아님). 발사/점등 프레임·나머지 7종 미제작 → NOT RUN 유지 |
| AC-03 | **부분**: 화차·장승·봉수·혼천의 실루엣 구분, 활성/비활성·연결/단절은 파생본으로 구분(라벨 숨김 `--labels=off` 캡처는 회차 3에서). 회수된 화차 자리 비움은 core 상태 그대로 |
| AC-08 | NOT RUN — **이제 사용자가 확인할 실제 샘플 화면이 있다**: `results/evidence/wp-005/captures/wp005_assets_*.png` |

알려진 한계: 원본이 정수 배율 픽셀 격자가 아니어서 축소 시 세부가 뭉개진다(다음 시안은 정수 배율 요청). 파생 비활성본은 임시다.

---

## GPT 부분 통합 기록 (PR #11, 브랜치 `wp/005-art-integration`, `f0c625a` → `c5ea366`; 병합 `f565a52`)

아래는 통합 브랜치의 결과 문서 원문(부분 통합 절 + GPT 시각 검수)이다. 시설 idle/active 파일은 이 브랜치의 것을 채택했고, 회차 2의 파생 비활성/단절 상태는 이 파일들로부터 다시 만들었다(회차 3).

### 2026-09-20 제작 리소스 부분 통합

- 기준 `cdfc88c` (PR #8), 구현 `f0c625a`. 이전 시설 pilot의 원본을 보존하고 기존 ArtSet 파이프라인에 통합했다.
- 35개 상태 파일 중 13개 적용: 시설 기본 상태 4개, 바닥 4프레임 1개, 지붕/담장 2개, 적 6상태×2프레임 6개. 적은 12×16, 시설은 40×40, 지형은 20×20. 원본/프롬프트는 `docs/art/source/wp005/`, 실제 규격·pivot·SHA는 `assets/art/wp005/integration_manifest.json`.
- 재생성: `godot --headless --path . --script res://game/tools/import_wp005_sources.gd`. 원본을 보존하며 알파 경계 추출·최근접 축소·시트 분리만 수행한다. 죽음 프레임은 이동 프레임과 같은 배율을 써서 잔해가 확대되지 않는다.
- 배포본에서 원본 PNG가 Godot 텍스처로 변환되는 문제를 확인하고 ResourceLoader 경로를 추가했다. 배포본의 원본 SHA는 동봉된 생성 manifest에서 읽는다. 파일 바이트 SHA와 배포 텍스처 자체 해시를 혼동하지 않는다.
- 최종 회귀 1,210 PASS / 0 FAIL, 71.3초. 증거 `results/evidence/wp-005/integration/test_report.txt`. 기존 테스트의 fixture 기반 상태 비교와 FX 검증 범위는 그대로다.
- 에디터 1080p/720p 각각 7장, release 1080p 7장과 상태 로그 저장. release에서도 13/35, 적 atlas=true 및 모든 원본 SHA 일치 확인. `integration/validation.json`에 exe 해시 기록. 로그의 개인 절대 경로는 저장소 상대 경로로 치환했다.
- 이번 통합본의 1,000체 성능 측정은 NOT RUN. 앞 회차 fixture 성능을 새 리소스의 성능으로 인용하지 않는다. 캡처의 동시 생존 수는 1,000체가 아니다.

#### GPT Review — 2026-09-20 부분 통합 시각 검수

최종 WP 판정은 **REVISE**, 작업 상태는 **IN_PROGRESS**다. AC-01은 필수 상태 22개가 누락되어 FAIL, AC-03은 비활성 시설이 회색 도형으로 대체되어 FAIL. AC-02는 길/담장 구분이 보이지만 타일 반복과 경계 보정이 남아 부분 확인. AC-04/05의 기존 자동 검증은 PASS. AC-06의 두 해상도 일반 전투는 확인했으나 1,000체 가독성은 NOT RUN. AC-07 통합 리소스 성능과 AC-08 사용자 스타일 확인은 NOT RUN이다.

화차·장승·봉수·혼천의의 기본 실루엣과 적 방향 동작은 실제 화면에서 확인했다. 720p에서는 작은 적 세부와 시설 이름이 조밀하다. 바닥 4종의 밝기 차이가 체크무늬처럼 보이며, 현재 기와는 반복 재질 수준으로 건물 실루엣은 아직 없다. 이를 완성된 도시 배경으로 승인하지 않는다.

다음 순서: (1) 비활성/단절/발사 시설 상태와 성문·거점 상태 제작, (2) 바닥 밝기·경계 및 건물 실루엣 보정, (3) 라벨 없는 시설 식별과 1,000체 캡처, (4) 동일 release의 greybox/sample 4종 성능 비교, (5) 실제 샘플 사용자 확인. WP-006 전체 맵 확장은 아직 시작하지 않는다.

---

### 2026-09-20 — 회차 3: PR #11 통합·GPT 검수 REVISE 반영 (D-051)

- 커밋: 병합 `f565a52` → 회차 3 구현 `33e2f8d` → 결과·증거 (이 문서 커밋).
- 반영한 검수 항목: (2) 바닥 4종 밝기 차이가 체크무늬로 보임 → 타일 계획을 기본 타일 약 69% + 변형 3종 희소 배치로 변경(`terrain_layer.gd`). (3) 라벨 없는 시설 식별과 1,000체 캡처 → 새 캡처 `wp005_dense[_720]`(D-027 벤치마크 부하, 라벨 on/off, 붕괴·재배치). (4) 같은 release의 greybox/sample 4종 성능 → `verify.ps1 -Wp005` 6d가 sample을 **배포 리소스 디렉터리**로 측정(fixture 아님). (1)(5)는 GPT 제작·사용자 확인 대기.
- 파생 상태: `scripts/art_convert_wp005.py`가 통합본 idle/active 파일에서 inactive/disconnected를 파생(채도 0.25·밝기 0.72, `derived_off`). 전용 프레임이 오면 교체.
- 배포본 로딩: PR #11의 `art_set.gd` ResourceLoader 폴백·`export_presets.cfg` include_filter 유지.

| 항목 | 결과 |
|---|---|
| 테스트 | **1,263 passed / 0 failed (63.6 s)**, 종료 0 |
| 캡처 `wp005_assets`/`_720` | greybox 대비 4체크포인트 상태 동일, 로드 17/35(누락 18), t15 bongsu/connected 8, hwacha/idle 4, jangseung/idle 2, sensor/active 4; 붕괴 후 bongsu/connected 2, bongsu/disconnected 6, hwacha/idle 1, hwacha/inactive 3, jangseung/inactive 2, sensor/active 1, sensor/inactive 3 |
| 캡처 `wp005_dense`/`_720` (AC-06) | t15 동시 생존 1000, 라벨 on/off 각 1장, 붕괴 t20.5, 재배치 t25.5 라벨 on/off |
| 성능 (같은 exe, 배포 리소스) | collapse_move/greybox 215.5 FPS · p95 13.31 ms, collapse_combat/greybox 239.4 FPS · p95 12.45 ms, collapse_move/sample 205.5 FPS · p95 13.68 ms (배포 리소스, 로드 17/35, atlas True), collapse_combat/sample 227.6 FPS · p95 12.69 ms (배포 리소스, 로드 17/35, atlas True) |
| AC-01 | 부분: 17/35 상태 파일(13 통합 + 4 파생). 발사·점등·거점·문·효과·표시 미제작 → NOT RUN 유지 |
| AC-02 | 부분: 바닥·지붕·담장 적용, 가장자리 타일·문 미제작. 체크무늬 완화는 캡처로 확인 |
| AC-03 | 부분: 활성/비활성·연결/단절은 파생본으로 구분, 라벨 없는 캡처 제공(`*_nolabels_*`) |
| AC-06 | 1,000체 캡처 제공, 가독성 판정은 GPT 시각 검수 |
| AC-07 | 배포 리소스로 4종 측정, 예산 충족 |
| AC-08 | NOT RUN — 사용자 확인 대기(`wp005_assets_*`, `wp005_dense_*`) |


### GPT Review — 2026-09-20 PR #11 재검토

검토 범위: PR #11 `cdfc88c` → `c5ea366` (구현 `f0c625a`). GitHub HEAD 일치 확인. diff, 명세, 실제 720p 붕괴/배치 화면, 저장된 캡처 로그·manifest·테스트 리포트를 검토하고 원본 적 시트의 알파 경계를 독립 측정했다. 이번 리뷰에서 전체 테스트·성능 측정을 재실행하지는 않았다.

**최종 REVISE.** 부분 통합은 확인되지만 아래 수정과 추가 증거가 필요하다.

1. **R-01 / P2 — 소멸 프레임 상단 잘림.** `game/tools/import_wp005_sources.gd:51-62`는 이동 8프레임만으로 공통 배율을 계산한다. 알파≥26 기준 이동 최대 높이261px, 소멸 첫 프레임 높이289px이므로 배율16/261 적용 후 소멸은12×18px이다. 16px 캔버스의 y=-2에 복사하면서 위쪽2px가 잘린다. 모든 상태를 수용하는 공통 배율/캔버스를 선택하거나 소멸 원본을 보정하고, 12프레임 전부 목적 프레임 경계 안에 들어가는지 검증한다. 로더의 12×16 규격 통과만으로 잘림을 검출할 수 없다.
2. **R-02 / P2 — AC-05 PASS 범위 과대 판정.** 앞 절의 AC-05 PASS를 아래 NOT RUN으로 정정한다. `tests/test_art_sample.gd`의 `_greybox_equals_sample` 및 보고서1244행 이후는 개발 fixture의 F2만 비교한다. 실제 리소스의 F1/F2/F4 각각에 대해 같은 명령·seed와 지정 체크포인트의 full_state 비교가 필요하다. 1,210개 기존 검증 통과 자체는 유효하지만 전체 AC-05 충족 증거는 아니다.
3. **R-03 / P2 — 붕괴 후 시설 정체성 소실.** 720p `wp005_sample_720_d_valid_preview_t23.5.png`에서 비활성 봉수·혼천의·장승이 기본 도형으로 바뀐다. 비활성 전후 같은 시설임을 읽을 수 있도록 형태를 유지하는 상태 리소스를 채운 뒤 이름 라벨을 숨긴 비교와 ID 범례를 제출한다. 부분 적용으로 이미 공개된 한계이며 새 전투 규칙 결함은 아니다.

| AC | 판정 | 근거 / 남은 작업 |
|---|---|---|
| AC-01 | FAIL | 13/35 PNG 상태 파일 로드. 필수 시설 상태·경계·성문·거점·FX 미완, 적 소멸 잘림. 누락22개 중 interaction_marks 5개는 절차적 도형이 허용되므로 22개 모두 신규 PNG 제작이 필수라는 뜻은 아님 |
| AC-02 | NOT RUN | 일반 화면은 확인했으나 근접/점유 정합 비교 증거 미완. 바닥 밝기 반복과 건물 실루엣 개선 필요 |
| AC-03 | FAIL | 비활성 시설 도형 대체, 라벨 없는 상태 식별 비교 미제출 |
| AC-04 | PASS | 저장된 자동 검증에서 이벤트 대응·pause120프레임·restart 정리 통과. pipeline 동작 판정이며 최종 FX 제작 승인은 아님 |
| AC-05 | NOT RUN | 기존 회귀1210/1210 및 fixture F2 비교는 통과. 실제 리소스 F1/F2/F4 전체 모드 비교 미완 |
| AC-06 | NOT RUN | 1080p/720p 일반 전투 캡처는 있으나 1000체 가독성·메뉴 전체 확인 미완 |
| AC-07 | NOT RUN | 통합 리소스 greybox/sample×move/combat release 성능4종 미측정 |
| AC-08 | NOT RUN | 이번 적용본에 대한 사용자 스타일 확인 및 최종 규격/가독성 승인 없음 |

배포본 manifest의 `sha256`는 원본 파일의 기록값이다. 에디터와 값이 같다는 사실만으로 배포 텍스처 픽셀 무결성까지 검증됐다고 해석하지 않는다. 다음 제출 시 디코딩한 RGBA 데이터 해시 비교를 추가하면 배포 변환 검증을 강화할 수 있다.

### 보완 회차 — 2026-09-20 R-01~03

- 기준 `c5ea366`, 구현 `f4b6c13`. 이전 리뷰를 보존하고 세 보완 항목을 처리했다.
- R-01: 배율 계산에 이동뿐 아니라 피격/소멸을 포함한 12프레임 전체 경계를 사용한다. 소멸 첫 프레임은 이제10×16이며 모든 프레임이12×16 캔버스에 들어간다. 경계 초과 시 가져오기를 실패 처리하고 `assets/art/wp005/enemy_geometry.json`에 원본/변환 크기를 기록한다. 원본은 유지했고, 미승인 v01 런타임 파일의 이전 바이트는 기준 커밋에서 복원 가능하다.
- R-02: `tests/test_art_integration.gd`가 실제 `res://assets/art/wp005`를 로드해 F1(정상 승리), F2(강제 붕괴/회수 배치 후 승리), F4(강제 붕괴/핵심 도달 패배)를 greybox와 비교한다. 같은 seed/명령, 초기·20초 직전·붕괴 직후(해당 시나리오만)·25초 명령 후·종료 full_state 일치. fixture 시험은 별도로 보존했다.
- R-03: 기존 생성 원본을 바탕으로 비활성 화차·장승·혼천의와 단절 봉수를 제작했다. 원본/전체 프롬프트는 `docs/art/source/wp005/REVISION_PROMPTS.md`. 시설 형태를 유지하며 소등/저채도로 상태를 구분한다. 현재17/35 PNG 파일 적용이다.
- 전체 회귀 **1,259 PASS / 0 FAIL**, 82.1초. 증거 `results/evidence/wp-005/revision1/test_report.txt`.
- 이름 라벨을 숨긴1080p/720p 각7장과 상태 로그, ID/좌표 범례 `revision1/FACILITY_LEGEND.md`를 추가했다. 붕괴 화면 draw 장부: 봉수 연결2/단절6, 화차 기본1/비활성3(회수 슬롯 포함), 장승 비활성2, 혼천의 활성1/비활성3. 비활성 시설이 회색 기본 도형으로 바뀌던 현상은 해소됐다.
- AC-05는 실제 리소스 세 시나리오 검증으로 PASS. R-01/02/03 수정 확인은 PASS이며 WP 전체 완료를 의미하지 않는다. 작은 화면의 소등 대비 보정, 미제작 발사/경계/성문/거점/FX, 1000체 가독성 캡처와 사용자 확인은 남아 있다.

#### 통합 리소스 성능 및 회차 판정

동일 release(`f4b6c13`, exe SHA-256 `469f2d697d0fb4cf063c6a4649d429ca18ab6d14b917af4a443c997c65e068f2`)·1920×1080·vsync0·warmup10초/measure60초. 기존 `perf_with_memory.ps1`로 모드/시나리오를 순차 측정했다. 실행은 숨긴 창에서 수행했으며 실제 GPU는 RTX4070SUPER/OpenGL이다. 장비·설정·구간 원시값·메모리는 각 JSON에 있다. 게임과 외부 샘플러의 exe 해시가 일치한다.

| 모드 | 시나리오 | 평균 FPS | p95 ms | alive 최소 | 판정 |
|---|---|---:|---:|---:|---|
| greybox | 이동 | 85.45 | 20.753 | 1000 | PASS |
| greybox | 전투 | 99.40 | 18.697 | 1000 | PASS |
| sample | 이동 | 83.35 | 21.061 | 1000 | PASS |
| sample | 전투 | 95.63 | 18.965 | 1000 | PASS |

수치의 정확한 원본은 `revision1/perf_summary.json` 및 `revision1/perf/`이다. `scripts/validate_wp005_revision.ps1`는 기존 D-027 validator를 재사용하고, frame_us_raw에서 FPS/p95와 alive_raw 최소를 독립 계산하며 동일 빌드·실제17개 파일·적 atlas를 확인한다. 6종 의미 이벤트 각1회, 모든 프레임의 구간 귀속, 각 구간 후보 평가, 재배치 성공, 재배치 후 화차42회 사격(전투)이 통과했다. sample 평균 FPS는 기준선 대비 이동 약2.5%, 전투 약3.8% 낮다. 단일 측정 차이의 원인을 확정하지 않는다.

**회차 판정:** R-01/02/03 보완 PASS, AC-03/05/07 PASS. AC-04는 이전 PASS 유지. AC-01 FAIL(나머지 필수 제작 미완), AC-02/06/08 NOT RUN(요구된 전체 증거/확인 미완). 따라서 **WP-005 전체는 REVISE / IN_PROGRESS 유지**다. 이번 성능 검증을 1000체 화면 가독성 검증으로 대체하지 않는다.

### 최종 통합 검증 — 2026-09-20 PR #12

PR #11은 이미 상위 브랜치에 병합되어 있었으므로 보완은 PR #12로 분리했다. 상위 `274ad7a`와 보완 `5d89cd3`을 `133f39e`에서 통합했다. 충돌 해결은 상위의 기본 sample 실행, 희소 바닥, dense 캡처, 추가53개 시험을 보존하고 비활성4종은 이번 전용 생성 그림을 선택했다. 이전 파생 그림과 모든 결과는 Git 이력/기존 증거 폴더에 남아 있다. `art_convert_wp005.py --check`는 전용 그림을 덮어쓰지 않고4종 해시 일치를 확인한다.

- 전체 자동 검증 **1,312 PASS / 0 FAIL**,82.4초. `revision1-merged/test_report.txt`.
- 배포본으로 `wp005_dense`, `wp005_dense_720`를 실행했다. 총10개 캡처 전부 alive=1000, png_saved=OK, sample 모드이며 라벨 on/off·붕괴·재배치를 포함한다. 각 실행 launch/t25.5의 enemy_sprites=true,17개 상태 파일 로드. `revision1-merged/dense_validation.json` 및 `captures/`.
- 720p 무라벨 전투와1080p 무라벨 재배치 화면을 시각 검수했다. 바닥의 큰 체크무늬는 줄었고, 비활성 시설은 기본 실루엣을 유지한다. 군집 흐름·진입 경로·재배치 화차는 확인되지만 어두운 길 위 적의 세부 대비는 약하다. 거점·경계·발사 등 누락 표현과 전체 메뉴/배치 표시 검수까지 완료한 것은 아니므로 AC-06 전체는 아직 승인하지 않는다.
- dense 캡처는 시뮬레이션6배속이므로 화면 HUD의 순간 FPS를 성능 합격 수치로 사용하지 않는다. 성능은 아래 동일 통합 release의 별도1배속 측정으로 판정한다.

통합 release SHA-256: `4eaf72dabac7e4b9f81f6146bf9fca2d6f6c54feaa9ee7c874629964ed0b3044`. 측정 구현은 `133f39e`, 조건은1920×1080/vsync0/warmup10초/measure60초이며 네 조건을 순차 실행했다.

| 모드 | 시나리오 | 평균 FPS | p95 ms | alive 최소 | 판정 |
|---|---|---:|---:|---:|---|
| greybox | collapse_move | 88.54 | 20.485 | 1000 | PASS |
| greybox | collapse_combat | 101.62 | 18.541 | 1000 | PASS |
| sample | collapse_move | 84.46 | 20.904 | 1000 | PASS |
| sample | collapse_combat | 97.26 | 18.732 | 1000 | PASS |

원시 배열 FPS/p95/최소 생존 수 검산, 동일 exe/구현 SHA, 실제17개 파일·적 atlas,6종 이벤트·구간 후보 평가·모든 프레임 귀속·배치 후42회 사격(전투), 외부 메모리 샘플러와 exe 해시 대조 모두 PASS. 검산 결과는 `revision1-merged/perf_summary.json`.

**최종 보완 판정: R-01~03 PASS, AC-03/04/05/07 PASS. WP 전체는 AC-01 FAIL 및 AC-02/06/08 미완으로 REVISE / IN_PROGRESS 유지.** 다음은 경계·성문·거점·발사/점등/FX 제작과 최종 화면 검수다. 전체 맵 양산은 아직 시작하지 않는다.

---

### 2026-09-20 — 회차 4: PR #12(GPT 보완 R-01~03 + 최종 통합) 채택과 재검증 (`079df43`)

- PR #12 `wp/005-art-integration`(`f4b6c13` → `133f39e` → `507846e`)는 회차 3 `274ad7a` 위에 쌓인 상위 집합이라 fast-forward로 채택했다. 내용: 전용 생성 비활성/단절 4종(원본 `docs/art/source/wp005/*_inactive|disconnected_source_v01.png`, `REVISION_PROMPTS.md`)이 회차 3의 파생본을 대체, 적 12프레임 공통 배율로 소멸 프레임 잘림 해소(`enemy_geometry.json`), 실제 리소스 F1/F2/F4 greybox==sample 비교(`tests/test_art_integration.gd`), 라벨 없는 캡처와 ID 범례(`revision1/FACILITY_LEGEND.md`), 검산 스크립트 `validate_wp005_revision.ps1`, GPT 재검토(REVISE, R-01~03) 및 보완 판정(R-01~03 PASS, AC-03/04/05/07 PASS, AC-01 FAIL, AC-02/06/08 미완).
- 되돌린 것 한 가지: PR #12가 `perf_with_memory.ps1`의 측정 창을 숨김(`-WindowStyle Hidden`)으로 바꿨다. WP-001~004 승인 증거는 보이는 창에서 측정했고 숨긴 창 수치(84~102 FPS)는 비교가 안 되므로 보이는 창으로 복원하고 아래를 다시 측정했다(`079df43`). PR #12의 숨긴 창 수치는 `revision1*/perf_summary.json`에 기록으로만 남는다.
- 재검증(`verify.ps1 -Wp005` 종료 0, 이 기기): 테스트 **1,312 passed / 0 failed (77.3 s)**; `wp005_assets` 로드 17/35(누락 18), 붕괴 후 전용 비활성 프레임 bongsu/connected 2, bongsu/disconnected 6, hwacha/idle 1, hwacha/inactive 3, jangseung/inactive 2, sensor/active 1, sensor/inactive 3; `wp005_dense` t15 동시 생존 1000. 성능(같은 exe `bdf80996d800…`, 보이는 창, 1920×1080, vsync 0, 10+60 s):

| 모드 | 시나리오 | 프레임 | 평균 FPS | p95 ms | alive min | 워킹셋 MB | 판정 |
|---|---|---:|---:|---:|---:|---|---|
| greybox | collapse_move | 12,843 | **214.0** | **13.70** | 1000 | 191.6→195.7 | PASS |
| greybox | collapse_combat | 14,326 | **238.8** | **12.61** | 1000 | 187.2→189.5 | PASS |
| sample | collapse_move (배포 리소스 17/35, atlas True) | 12,293 | **204.9** | **13.84** | 1000 | 190.2→135.5 | PASS |
| sample | collapse_combat (배포 리소스 17/35, atlas True) | 13,682 | **228.0** | **12.74** | 1000 | 194.5→141.6 | PASS |

- AC 요약(회차 4 기준): AC-03 PASS(전용 비활성·라벨 없는 식별·범례), AC-04 PASS, AC-05 PASS(실제 리소스 F1/F2/F4 + fixture), AC-07 PASS(보이는 창 4종, 예산 안), AC-01 FAIL(가장자리·문·발사·점등·거점·효과·표시 미제작), AC-02·AC-06 부분(근접/점유 정합·메뉴 전체 검수 미완), AC-08 NOT RUN(사용자 확인 대기). WP 전체는 REVISE / IN_PROGRESS.

---

### 2026-09-20 — 회차 5 계획 (인계문 `docs/CLAUDE_HANDOFF.md`, 기준 `15ef03e`)

잔여 목록과 도구 점검, 이번 회차의 작업·검증 계획이다. 계획 커밋 뒤 구현하고 결과를 아래에 덧붙인다.

- 잔여 필수 상태(PNG): `terrain_sample/edge` 8, `building_sample/gate` 1, `hwacha/fire` 3, `bongsu/pulse` 2, `outer_post`·`core_post` 각 3, `combat_fx` fire/impact/collapse 각 3 = **29 프레임(15 파일)**. `interaction_marks` 5는 WP가 절차적 도형을 허용하므로 PNG 제작 대상에서 제외하고 manifest에 `PROCEDURAL`로 연결한다.
- 도구: 이 환경에는 여전히 이미지 생성 도구가 없다(Pillow·Godot Image API만). 위 15파일은 [WP005_REQUEST](../docs/art/source/WP005_REQUEST.md) 접수 현황에 ID·상태·규격·입력 원본을 명시해 GPT 제작 단계로 반환한다. 기다리는 동안 가져오기·검증·표현 보정을 진행한다.
- 구현(렌더링만, 전투 규칙·적 수·점유·경로 불변):
  1. 적 대비: 적 아틀라스 셰이더에 1텍셀 밝은 테두리(`--art-outline=on|off`, 기본 on)를 추가해 어두운 길 위 가독성을 올린다. 리소스 픽셀은 바꾸지 않고 배포본 성능을 다시 잰다.
  2. 소등 식별: 비활성·단절 시설 위에 절차적 소등 표시(회색 원 + 사선)를 그려 색 변화에만 의존하지 않게 한다(ART_GUIDE).
  3. 경계: `terrain_sample/edge` PNG가 올 때까지 벽 접면에 절차적 가장자리 선(계획 항목 그대로)을 그린다. 시설 40×40 점유 사각형·20px 격자 오버레이 토글을 추가한다.
  4. 근접 증거: 캡처 스텝 `zoom`(Camera2D)과 시나리오 `wp005_closeup`(광장·외곽 거점·B 셀 3배 근접, 점유 오버레이 on/off).
  5. 메뉴: `wp004_ui`/`_720`을 `--art=sample`로 실행해 두 해상도 메뉴·문자·배치 표시를 샘플 아트 위에서 캡처한다.
  6. 1,000체: `wp005_dense`에 테두리 off 비교 캡처를 더한다.
- 검증: 회귀 전체 + 새 케이스(옵션 항목 보고, 테두리 uniform, 카메라 스텝, 점유 토글), `verify.ps1 -Wp005`(assets·dense·closeup·menus 캡처, 배포 리소스 성능 4종 보이는 창). 결과·증거는 새 회차로 기록하고 REVIEW 전환은 필수 제작 완료 후에만 한다.

#### 회차 5 결과 (구현 `6e10da5`, `verify.ps1 -Wp005` 종료 0)

| 항목 | 결과 |
|---|---|
| 테스트 | **1,322 passed / 0 failed (81.3 s)**, 종료 0 (새 검사: 선택 항목 보고 5건, 테두리 uniform on/off, 3배 카메라 생성·제거·전투 상태 불변, 점유 오버레이 기본 off) |
| `wp005_assets`/`_720` | 로드 17/35, 필수 누락 13, 선택(표시) 누락 5; t15 절차적 가장자리 142개, 표시 장부 attach_dash 8, link_line 8; 붕괴 후 표시 장부 attach_dash 2, link_line 1, off 13, recovery_slot 1 |
| `wp005_dense`/`_720` (AC-06) | t15 동시 생존 1000, 라벨 on/off·테두리 on/off 캡처, 붕괴·재배치 |
| `wp005_closeup` (AC-02) | 5장(광장 3배 점유 격자 on/off, 외곽 거점 붕괴, B 셀 미리보기 격자, B 재배치), zoom 3.0, 점유 오버레이 1 |
| 메뉴 over 샘플 아트 (AC-06) | `captures/menus/` 22장(`wp004_ui`·`_720` 각 11장 + 로그), 패배/승리 결과 화면 포함 |
| 성능 (같은 exe `9cb21c44378f…`, 보이는 창, 테두리 on) | 아래 표 |

| 모드 | 시나리오 | 프레임 | 평균 FPS | p95 ms | alive min | 워킹셋 MB | 판정 |
|---|---|---:|---:|---:|---:|---|---|
| greybox | collapse_move | 9,315 | **155.2** | **17.76** | 1000 | 179.8→132.8 | PASS |
| greybox | collapse_combat | 11,558 | **192.6** | **15.02** | 1000 | 185.3→160.8 | PASS |
| sample | collapse_move (배포 리소스 17/35, atlas True, 테두리 on) | 8,930 | **148.8** | **16.24** | 1000 | 202.3→205.3 | PASS |
| sample | collapse_combat (배포 리소스 17/35, atlas True, 테두리 on) | 10,219 | **170.3** | **15.01** | 1000 | 190.3→1 | PASS |

- AC 요약(회차 5): AC-03/04/05/07 PASS 유지(AC-07은 테두리 on 배포 리소스로 재측정), AC-02 부분→근접·점유 격자 증거 추가(가장자리 PNG 미제작, 절차적 선), AC-06 부분→1,000체 테두리 비교·메뉴 두 해상도 증거 추가(가독성 판정은 GPT), AC-01 FAIL(15파일 제작 대기), AC-08 NOT RUN(사용자 확인 대기). **REVIEW 전환 조건(필수 제작 완료) 미충족 → IN_PROGRESS 유지.**
- 사용자 확인용 화면(갱신): `captures/wp005_assets_*`, `wp005_dense_*_nolabels_*`, `wp005_dense_*_nooutline_*`(테두리 비교), `wp005_closeup_*`, `captures/menus/*`.
- 성능 비고: 이번 회차 greybox 수치(155.2 / 192.6 FPS)는 회차 4(214.0 / 238.8)보다 낮다. greybox 렌더 경로는 회차 5에서 바뀌지 않았고(테두리는 sample 셰이더에만, 소등·점유 표시는 sample·캡처에만) 같은 기기의 회차 간 편차(회차 1~5: 178·195·215·214·155)로 본다. 같은 exe 안의 상대 비교는 sample이 greybox 대비 이동 −4%, 전투 −12%(p95 +0.0 / −1.5 ms)이며 모두 예산(≥60 FPS, ≤25 ms) 안이다. 원인 규명용 통제 A/B는 NOT RUN.

#### 사용자 확인 기록 (AC-08)

| 날짜 | 확인한 빌드 | 방식 | 사용자 응답 | 판정 |
|---|---|---|---|---|
| 2026-09-20 | `wp/005-art-sample` `7157654` (구현 `226b011`), 로컬 `godot --path .` 일반 실행(sample 기본) | 사용자 직접 실행. 첫 실행은 로컬이 `main`에 있어 회색상자만 보였고, 브랜치 전환 후 재실행 | "다시 테스트해봤는데 이제 리소스 보인다" | **표시 확인**(리소스가 실제 화면에 나온다는 확인). 스타일 방향에 대한 의견은 아직 없음 → AC-08은 NOT RUN 유지. 무응답을 승인으로 간주하지 않는다 |

### 2026-09-24 — 회차 6: V-01 기본 표시 정리 (D-053, 게임샷 개선 계획 첫 항목)

- 구현 **`60fc75f`**, 이 절의 증거는 그 커밋에서 `verify.ps1 -Wp005` 종료 0. 계획: [WP005_VISUAL_REVISION_PLAN](../docs/art/WP005_VISUAL_REVISION_PLAN.md) V-01("Claude 적용, GPT 검수").
- 무엇을 바꿨나(표시만, 전투 불변): 일반 실행의 기본을 **플레이어 보기**로 한다. 밀도 존·사거리 원·상세 패널을 접고(Z/G/D로 그대로 열림), 상단 HUD를 웨이브·방어 상태 / 두 거점 HP·처치·도달 / 붕괴 설명 또는 회수 지시 / 짧은 조작 줄 4줄로 줄였다. 엔진·FPS·누계·존·화차별·봉수망 줄은 상세 패널로 옮겼다. 시설 이름은 짧게(그룹·탐지 수치는 D를 켤 때), 외곽 거점 HP 막대·문구는 마커 위로 옮겨 화차·중영 이름과 떨어뜨렸다. 비어 있는 좌하단 패널은 숨긴다. `--perf`/`--capture`는 개발자 보기를 유지해 기존 증거가 그대로 재현된다. `--view=player|dev`로 고를 수 있다.
- 측정 방법: 캡처 `wp005_v01[_720]`이 F2 타임라인의 5개 지점에서 전투를 멈춘 채(hold) 같은 틱을 개발자 보기(이전 기본) / 플레이어 보기 / 이름 끈 플레이어 보기로 찍는다. 오버레이가 그린 이름·거점 문구·막대·구역·회수 문구의 상자를 기록하고 겹치는 쌍을 센다(HUD 패널과 지도 사이, 스프라이트와 문구 사이의 겹침은 이 수치에 들어가지 않는다).
- 테스트: **1,366 passed / 0 failed** (새 스위트 44건: 실행 방식별 기본값, HUD 순서, 모든 토글, 이름 문구, 두 보기의 전투 상태 동일, 캡처 hold).

| 해상도 | 지점 | 틱 | HUD 줄 수 개발자 / 플레이어 | 문구 상자 | 겹치는 쌍 개발자 → 플레이어 |
|---|---|---:|---|---|---|
| 1080p | a_battle_t15 | 900 | 7 / 4 | 26 / 26 | 1 → 0 |
| 1080p | b_collapse_t20.5 | 1230 | 7 / 4 | 27 / 27 | 0 → 0 |
| 1080p | c_recovery_preview_t23.5 | 1410 | 7 / 4 | 27 / 27 | 0 → 0 |
| 1080p | d_recovery_placed_t25.5 | 1530 | 7 / 4 | 26 / 26 | 0 → 0 |
| 1080p | e_inner_fire_t45 | 2700 | 7 / 4 | 26 / 26 | 0 → 0 |
| 720p | a_battle_t15 | 900 | 7 / 4 | 26 / 26 | 1 → 0 |
| 720p | b_collapse_t20.5 | 1230 | 7 / 4 | 27 / 27 | 0 → 0 |
| 720p | c_recovery_preview_t23.5 | 1410 | 7 / 4 | 27 / 27 | 0 → 0 |
| 720p | d_recovery_placed_t25.5 | 1530 | 7 / 4 | 26 / 26 | 0 → 0 |
| 720p | e_inner_fire_t45 | 2700 | 7 / 4 | 26 / 26 | 0 → 0 |

- 결과: 같은 틱에서 플레이어 보기의 겹침은 모든 지점·두 해상도에서 0이다. 개발자 보기에서 측정된 겹침은 t15의 외곽 거점 HP 막대와 화차·중영 이름 한 쌍이며, 플레이어 보기에서는 막대를 위로 옮겨 사라졌다.
- 관측(Claude 육안, 판정 아님): 플레이어 보기의 전장은 원과 수치가 빠져 길·시설·적이 먼저 보인다. 샘플 바닥(황토색) 위에서 주황·빨강 문구(외곽·핵심 거점 HP, 봉수 이름)는 대비가 약하다. 이는 V-02(적·시설 대비, 팔레트) 범위라 이번에 색을 바꾸지 않았다. 720p에서 상단 HUD 문구는 작지만 4줄이라 겹치지 않는다.
- 성능(렌더링 변경 후 같은 release, 계획 증거 5): exe `2fa55bd9e7e8…`, 보이는 창.

| 모드 | 시나리오 | 평균 FPS | p95 ms | alive min | 구현 SHA |
|---|---|---:|---:|---:|---|
| greybox | collapse_move | **227.8** | **12.50** | 1000 | `60fc75f` |
| greybox | collapse_combat | **247.6** | **11.84** | 1000 | `60fc75f` |
| sample | collapse_move | **182.4** | **13.78** | 1000 | `60fc75f` |
| sample | collapse_combat | **203.0** | **12.77** | 1000 | `60fc75f` |

- 성능 수치가 회차 5(greybox 155.2/192.6, sample 148.8/170.3)보다 높다. 이번 변경은 문구·원 그리기를 줄였을 뿐이라 이 차이를 설명하지 못한다. 같은 장비·같은 창 조건이지만 두 측정 사이의 원인(시스템 상태 등)은 확인하지 않았다(A/B NOT RUN). 판정은 예산 대비로만 한다.
- 증거: `results/evidence/wp-005/captures/v01/` (PNG 15장 × 2 해상도 + 로그), `perf/`, `tests/test_report.txt`.
- 남은 것: V-02(적 몸통 중간톤·시설 팔레트, GPT 제작), V-03(건축 실루엣, GPT 제작), V-04(점등·발사·소등 효과), 잔여 리소스 15파일. AC-08은 사용자 스타일 확인 전까지 NOT RUN. WP-005 상태 IN_PROGRESS 유지.

#### 회차 6 보완 (2026-09-24): 플레이어 HUD 글자 18 px

- 구현 **`5f6333a`**, 같은 커밋에서 `verify.ps1 -Wp005` 종료 0. 위 표의 캡처·성능은 이 커밋으로 다시 만들어졌다(앞 커밋 `60fc75f`의 수치는 git 이력 `4cc0490`에 보존).
- 이유: 회차 6 관측에서 4줄 플레이어 HUD가 1280×720에서 약 10 px로 작았다. 플레이어 보기에서만 15 → 18 px(720p에서 약 12 px). 지도 위 이름 크기는 그대로 두어 겹침 수치가 유지된다.
- 결과: 테스트 **1,368 passed / 0 failed**(글자 크기 검사 2건 추가), 플레이어 보기 문구 겹침 1080p 0 / 720p 0, HUD 4줄, 패널은 내곽 왼쪽·광장 위에 머문다.
- 성능(release `b36ab01fa857…`, 구현 `5f6333a`): greybox collapse_move 230.9 FPS / p95 12.49 ms · greybox collapse_combat 253.2 FPS / p95 11.67 ms · sample collapse_move 184.0 FPS / p95 13.92 ms · sample collapse_combat 203.6 FPS / p95 12.72 ms.

