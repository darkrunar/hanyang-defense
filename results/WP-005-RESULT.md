# WP-005 시설 4종 시험 적용 결과

- 날짜: 2026-09-20. Status: IN_PROGRESS. GPT Review: PENDING.
- 계획 기준: 03f78d4 (WP-004 main 51d89ed 기반). 구현: 26b9d70.
- 사용자 “적용” 요청 범위: 생성된 시설 4종의 실제 전장 시험 적용. WP-005 전체 완료가 아님.

## 변경과 실행

화차·장승·봉수대·혼천의를 원본 PNG의 알파 영역에서 읽어 최대36×36px로 기존40×40px 점유 안에 그린다. 원본을 잘라 덮어쓰지 않으며 텍스처/영역은 캐시한다. 기본 일반 실행은 sample, 기존 perf/capture는 명시 옵션 없을 때 greybox다. 비활성 시설은 어둡게 표시하고 X를 추가한다. 점유·연결·회수는 기존 전투 상태를 그대로 읽는다.

```text
godot --path . -- --art=sample
godot --path . -- --art=greybox
godot --headless --path . --script res://tests/run_tests.gd -- --report=<absolute_report_path>
godot --path . --rendering-driver opengl3 --script res://results/evidence/wp-005/capture_pilot.gd
```

## 검증

- 전체 회귀: 1,106 PASS / 0 FAIL, 69.5초, 종료0. evidence/wp-005/test_report.txt.
- 실제 1080p/720p sample/greybox 캡처 생성 및 눈검수. render_checks.json의 렌더 전후 구조화 전투 상태 비교4건 모두 true. 이는 전체 F1/F2/F4 양쪽 모드 비교를 대체하지 않는다.
- 붕괴 후 비활성 시설 몸체 유지와 회수된 화차 제거 확인: sample_collapsed_720.png.
- Windows release export 성공, 120프레임 짧은 실행 종료0·stderr 없음. 실행파일은 별도 로컬 산출물이며 저장소에 커밋하지 않음.
- 1,000체 release 성능, 전체 샘플 사용자 확인: NOT RUN.

## 시각 검토와 남은 범위

시설 실루엣은 구분되며 발광보다 실제 연결선/라벨을 우선한다. 원본1254px를 작은 표시 영역에 그리므로 720p의 세부 묘사가 작다. 현재는 정적 시설 시험 적용이며 40px 원본 픽셀 정리·방향/프레임 통일·발사 애니메이션·전용 비활성/단절 리소스는 미완료다. 지형·적·거점·효과는 기존 도형이다. 회수 대기 아이콘도 기존 표시다. 큰 텍스처의 메모리 최적화와 시작 시 알파 영역 계산을 사전 메타데이터로 옮기는 작업은 후속 범위다.

## WP-005 AC 현황

AC-01~04, AC-06: 일부 작업만 수행되어 전체 기준 판정 NOT RUN. AC-05: 기존 회귀와 렌더 상태 비교는 PASS, 전체 F1/F2/F4 모드 비교 NOT RUN. AC-07/08: NOT RUN. 전체 WP PASS/DONE 또는 최종 스타일 승인으로 표시하지 않는다.

## 다음 작업

40px 크기에 맞춘 픽셀 보정과 시설 상태 프레임 제작, 지형/적/거점 최소 묶음 적용 후 전체 AC를 검증한다. 원본 제작 지시·도구는 docs/art/source/wp005/PROMPTS.md, 개별 상태는 ASSET_MANIFEST.csv에 기록했다.
