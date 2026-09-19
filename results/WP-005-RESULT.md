# WP-005 Result

- 작성일: 2026-09-20
- WP / 상태: WP-005 그래픽 기준 및 광화문 앞 샘플 적용 / **IN_PROGRESS** (파이프라인·검증 기반 완료, 리소스 11종은 GPT 제작 단계 대기, 에셋 적용·사용자 스타일 확인 전 → REVIEW 아님)
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
