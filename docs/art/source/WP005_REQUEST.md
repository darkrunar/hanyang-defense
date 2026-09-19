# WP-005 리소스 제작 요청 · 파일 계약 (Claude Code → GPT 제작 단계)

작성일: 2026-09-20 · 기준: [ART_GUIDE](../ART_GUIDE.md), [ASSET_MANIFEST](../ASSET_MANIFEST.csv), [WP-005](../../../backlog/WP-005.md) §진행 순서 2, D-049.

## 도구 점검 결과 (WP-005 진행 순서 2)

- Claude Code 실행 환경에는 **이미지 생성 도구가 없다**. 사용 가능한 것: Python 3.13 + Pillow 12.2 / numpy(자동 보정·검사·아틀라스 합성), Godot 4.7 `Image` API(헤드리스 PNG 읽기/쓰기·검증), git. ImageMagick·Figma·Unity 접근 불가.
- 따라서 아래 **11개 asset ID 전부**를 GPT 제작 단계로 반환한다. 제작 완료를 주장하지 않는다. 파일이 오기 전까지 `--art=sample`은 없는 요소를 회색상자로 그리고 누락 목록을 로그에 남긴다.
- 파이프라인(로더·아틀라스·타일·FX·캡처·성능 측정)은 **개발용 fixture**(`game/tools/wp005_dev_fixture.gd`가 `user://wp005_art_fixture`에 생성하는 도형 PNG)로 검증했다. fixture는 에셋이 아니며 `assets/`·manifest에 들어가지 않는다.

## 가져오기 계약 (로더 `game/scenes/art_set.gd`)

- 디렉터리: `assets/art/wp005/<subdir>/`. 런타임은 `res://assets/art/wp005`를 읽고 `--art-dir=<경로>`로 대체할 수 있다.
- 파일명: `<asset_id>_<state>_v01.png`. 수정본은 `v02`… (로더 기본 `v01`; 채택 버전은 manifest에 기록).
- 형식: 투명 RGBA PNG, nearest 필터(프로젝트 설정), 프리멀티플라이 없음. 개별 원본 보존.
- 프레임: 상태가 N프레임이면 **가로 스트립 1장**(폭 = 캔버스 폭 × N, 여백 없음, 높이 = 캔버스 높이). 로더가 폭을 N으로 나눠 자르므로 폭이 N의 배수가 아니면 거절하고 누락으로 기록한다.
- 기준점(pivot, 캔버스 픽셀): 기본 규칙은 ART_GUIDE대로. 시설·거점은 `(폭/2, 높이-20)`이 시설 발자국(40×40) 중심에 놓인다(40×40 캔버스면 정중앙). 적은 `(폭/2, 높이)` = 몸통 하단 중심. 효과·타일·표시는 캔버스 중앙. 다른 값이 필요하면 `assets/art/wp005/pivots.json`에 `{"파일명.png": [px, py]}`.
- 적 아틀라스: 로더가 6개 상태 12프레임을 4열×3행, 2px 여백으로 합성한다(상태별 프레임 크기 동일해야 함). 순서: walk_down 0-1, walk_up 2-3, walk_left 4-5, walk_right 6-7, hit 8-9, despawn 10-11.

## 접수 현황 (2026-09-20 갱신)

- 접수: `hwacha`(idle), `jangseung`(idle), `bongsu`(connected), `sensor`(active) 원본 4장 — GPT 파일럿 브랜치(PR #10), `docs/art/source/wp005/`. `scripts/art_convert_wp005.py`로 40×40 계약 파일 변환(D-050). `inactive`/`disconnected`는 원본이 없어 파생본(채도·밝기 감소)으로 임시 적용 — **전용 프레임 요청 유지**.
- 접수 2(PR #11 `f0c625a`, 통합 브랜치): `terrain_sample/ground`(4), `building_sample/roof`·`wall`, `enemy_basic` 6상태 12프레임 — 원본 `enemy_sheet_source_v01.png`·`terrain_sheet_source_v01.png`, `game/tools/import_wp005_sources.gd`로 슬라이싱. 시설 idle/active도 이 도구 결과로 교체(D-051). 파생 inactive/disconnected 4장은 `scripts/art_convert_wp005.py`.
- 미접수(17/35 적용 후 남은 18): `terrain_sample/edge`(8), `building_sample/gate`, `hwacha/fire`(3), `bongsu/pulse`(2), `outer_post`·`core_post` 각 3, `combat_fx` 3×3, `interaction_marks` 5. 전용 `inactive`/`disconnected` 프레임도 여전히 요청(현재는 파생본). 아래 목록 그대로 유효.
- 접수 3(PR #12 `f4b6c13`): 전용 `hwacha/inactive`, `jangseung/inactive`, `bongsu/disconnected`, `sensor/inactive` 원본 4장(`REVISION_PROMPTS.md`) → 파생본 대체. 17/35.
- **회차 5 반환 목록(GPT 제작 단계, 2026-09-20)** — 이 환경에는 이미지 생성 도구가 없어 아래를 요청한다. 입력 원본은 기존 `docs/art/source/wp005/`의 같은 시설/시트를 기준으로 한다.

| asset_id/state | 프레임 | 캔버스 | 파일 | 입력 원본·지시 |
|---|---|---|---|---|
| terrain_sample/edge | 8 | 20×20 | terrain_sample_edge_v01.png | `terrain_sheet_source_v01.png` 바닥 톤에 맞춘 벽 접면 가장자리 0-3(N/E/S/W), 안쪽 모서리 4-7. 투명 배경, 바닥 위에 겹침 |
| building_sample/gate | 1 | 폭 80 권장 | building_sample_gate_v01.png | 스타일 시트의 광화문 문. 셀 46..49,15 중앙 배치 |
| hwacha/fire | 3 | 40×40 | hwacha_fire_v01.png | `hwacha_idle_source_v01.png` 편집: 점화 3단계, 실루엣 유지 |
| bongsu/pulse | 2 | 40×40 | bongsu_pulse_v01.png | `bongsu_active_source_v01.png` 편집: 등화 밝기 2단계 |
| outer_post normal/hit/collapsed | 각 1 | 40 바닥 기준 | outer_post_{normal,hit,collapsed}_v01.png | 외곽 거점(석축 초소): 정상/피격 섬광/붕괴 잔해 |
| core_post normal/hit/collapsed | 각 1 | 40 바닥 기준 | core_post_{normal,hit,collapsed}_v01.png | 핵심 시설(궁성 전각): 정상/피격/붕괴 |
| combat_fx fire/impact/collapse | 각 3 | 24·24·48 권장 | combat_fx_{fire,impact,collapse}_v01.png | 발사 섬광/탄착 링/붕괴 파열, 투명 배경, 중앙 기준점 |

`interaction_marks` 5종은 절차적 도형으로 확정(manifest `PROCEDURAL`), PNG 요청 제외. 가장자리 타일이 올 때까지 벽 접면은 절차적 선으로 그린다.
- 원본 형식 참고: 1254×1254 RGBA에 3px 내외 런 길이의 "픽셀아트풍" 렌더였다. 다음 시안은 가능하면 **정수 배율(예: 40×40을 16배 = 640×640)로 확대된 실제 픽셀 격자**로 주면 축소 손실 없이 nearest 축소가 된다.

## 요청 목록 (ID · 상태 · 프레임 · 캔버스 · 파일)

| asset_id | subdir | state | 프레임 | 캔버스(px) | 파일명 | 비고 |
|---|---|---|---|---|---|---|
| terrain_sample | terrain | ground | 4 | 20×20 | terrain_sample_ground_v01.png | 흙길/석재/잔디 바닥 4종. 셀 해시로 분산 배치 |
| terrain_sample | terrain | edge | 8 | 20×20 | terrain_sample_edge_v01.png | 0-3 = 벽이 N/E/S/W에 접한 가장자리, 4-7 = 안쪽 모서리 NE/SE/SW/NW. 바닥 위에 겹쳐 그림(투명 배경) |
| building_sample | buildings | roof | 1 | 20배수 | building_sample_roof_v01.png | 거리에 면하지 않는 벽 블록에 패턴으로 반복 |
| building_sample | buildings | wall | 1 | 20배수 | building_sample_wall_v01.png | 거리에 면한 벽 셀에 패턴으로 반복(담장) |
| building_sample | buildings | gate | 1 | 자유(폭 80 권장) | building_sample_gate_v01.png | 광화문 문(셀 46..49, 15) 중앙에 1회 |
| hwacha | facilities | idle / inactive | 1 / 1 | 40×H | hwacha_idle_v01.png, hwacha_inactive_v01.png | 비활성은 소등 |
| hwacha | facilities | fire | 3 | 40×H | hwacha_fire_v01.png | 실제 발사(muzzle 0.12 s) 동안 순서대로 |
| jangseung | facilities | idle / inactive | 1 / 1 | 40×H | jangseung_idle_v01.png, jangseung_inactive_v01.png | 비활성도 차단 몸체 유지 |
| bongsu | facilities | connected / disconnected | 1 / 1 | 40×H | bongsu_connected_v01.png, bongsu_disconnected_v01.png | 실제 그룹 연결 상태 |
| bongsu | facilities | pulse | 2 | 40×H | bongsu_pulse_v01.png | 연결 시 0.5 s 간격 점등(있으면 connected 대신 사용) |
| sensor | facilities | active / inactive | 1 / 1 | 40×H | sensor_active_v01.png, sensor_inactive_v01.png | 고리 실루엣 |
| outer_post | objectives | normal / hit / collapsed | 1 / 1 / 1 | 40 바닥 기준, 높이 자유 | outer_post_normal_v01.png … | hit = 피해 후 0.4 s |
| core_post | objectives | normal / hit / collapsed | 1 / 1 / 1 | 40 바닥 기준 | core_post_normal_v01.png … | collapsed = 핵심 HP 0 |
| enemy_basic | enemies | walk_down / walk_up / walk_left / walk_right | 2씩 | 12×16(최초) | enemy_basic_walk_down_v01.png … | 방향은 경로 흐름장의 다음 셀로 결정, 2프레임 교대(6 Hz + 개체 위상) |
| enemy_basic | enemies | hit / despawn | 2 / 2 | 12×16 | enemy_basic_hit_v01.png, enemy_basic_despawn_v01.png | 실제 피해/소멸 위치에 효과로 재생(0.12 / 0.20 s) |
| combat_fx | fx | fire / impact / collapse | 3 / 3 / 3 | 자유(24·24·48 권장) | combat_fx_fire_v01.png … | 발사 = 화차 중심, 탄착 = 조준점, 붕괴 = 외곽 거점. 각각 0.18 / 0.30 / 0.90 s |
| interaction_marks | marks | link_ok / link_cut / recovery_wait / place_ok / place_bad | 1씩 | 자유(16 권장) | interaction_marks_link_ok_v01.png … | 없으면 기존 절차적 도형 유지. link_ok = 봉수 간선 중점, link_cut = 미부착 단말 위, recovery_wait = 대기 화차 위, place_* = 배치 고스트 중앙 |

높이 `H`는 40 기본, 상단 돌출 시 40 초과 허용(pivot 규칙 참조). 총 35파일.

## 반환 시 함께 줄 것

- 생성 도구 이름·제작일·제작 지시/작업 식별자, 권리 검토 결과(ART_GUIDE 파일과 추적).
- 각 파일의 실제 캔버스·프레임 수·기준점(기본 규칙과 다르면 pivots.json 값).
- Claude는 받은 파일을 `assets/art/wp005/`에 넣고 manifest의 `actual_path/pivot/sha256/status`를 갱신한 뒤 `--art=sample` 캡처·회귀·성능을 다시 낸다. 규격 불일치는 누락 목록으로 되돌린다.
