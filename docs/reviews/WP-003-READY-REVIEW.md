# WP-003 READY 기획 검증 · 2026-09-15

- 대상 코드/사전 검토 기준: `2efac7d` (PR #3 병합).
- GPT 재실행: Godot 4.7.stable.official.5b4e0cb0f, 두 probe 모두 종료코드0.
- 각 실행은 `godot --headless --path . --script <아래 res 경로> -- --out=<절대 JSON 출력 경로>`.

| probe | 재실행 JSON SHA256 | 저장소 기존 JSON과 비교 |
|---|---|---|
| `res://results/evidence/wp-003/pre-review/geometry_probe.gd` | `e4601dd05206a03c9aaac814b4f2d18e3f58ac91b0e16e2796938ec73a2ec570` | 바이트 동일 |
| `res://results/evidence/wp-003/pre-review/zone_ab_probe.gd` | `e3805b0cf13a3af1eb0075109ba4f3536ed815730ad7c5adc220eb306978ce8e` | 바이트 동일 |

동일 JSON을 중복 추가하지 않는다. 기존 `pre-review/`의 두 JSON을 함께 확인한다.

확인 범위: 기존 코어에서 두 목표/장승 유지 경로, 시설 구역, A/B 합법 후보와 거리·부착·센서 기하. 실제 전투 후 점유·새 붕괴 코드·승패·1000체 성능은 아직 구현 검증하지 않았다.

기획 처리: D-a~D-h와 P-012~016을 D-019~027 및 WP-003 READY v1.0으로 확정. F3는 다른 화차의 효과 가림을 통제하기 위해 H4를 비활성한 동일 스냅샷 비교로 고정하고, F2에서 전체 시설과 실제 웨이브를 별도로 검증한다. Z9 r50 유지, 개체별 관측만 보장한다.

최종 **READY (구현 착수 가능)**. 구현 AC-01~08은 모두 **NOT RUN**. 이 파일은 구현 결과나 GPT 최종 PASS 문서가 아니다.
