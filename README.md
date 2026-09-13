# 한양 디펜스 · Hanyang Defense

**한양 전체를 무기화하는 대규모 전투 디펜스.** 조선 사이버펑크 세계에서 적을 유도·압축하고 도시의 시설을 연결해 싸우는 로그라이트 디펜스 프로젝트입니다.

현재 단계는 **기획 및 구현 핸드오프 초기화**입니다. 실행 가능한 게임, 엔진 프로젝트, 자동 에이전트 연동은 아직 없습니다.

## 게임의 중심

- 플레이어: 적의 흐름을 바꾸고 위험한 전선을 재편한다.
- 시설: 지속 화력을 제공하고 봉수망으로 표적을 공유한다.
- 도시: 성문·골목·수로·관청이 하나의 전투체계가 된다.
- 실패 대응: 외곽 방어선 붕괴 후 안쪽으로 후퇴하며 병목을 다시 만든다.

**전투 → 자원 확보 → 건설 → 연결 → 검증 → 재편 → 전투**

## 문서 지도

| 문서 | 내용 |
|---|---|
| [CLAUDE.md](CLAUDE.md) | 구현 규칙, 테스트와 결과 전달 계약 |
| [GAME_DESIGN](docs/GAME_DESIGN.md) | 경험 목표, 세계관, 게임 범위 |
| [CORE_LOOP](docs/CORE_LOOP.md) | 코어 루프와 Mermaid 다이어그램 |
| [SYSTEM_SPEC](docs/SYSTEM_SPEC.md) | 시스템 책임, 규칙, 검증 방법 |
| [DECISIONS](docs/DECISIONS.md) | 확정 사항, 초기 제안, 미결정 사항 |
| [ROADMAP](docs/ROADMAP.md) | 단계별 목표와 통과 조건 |
| [WP-001](backlog/WP-001.md) | 대량 적 이동 → 병목 → 화차 사격 |
| [WP-002](backlog/WP-002.md) | 봉수망과 시설 간 표적 공유 |
| [WP-003](backlog/WP-003.md) | 웨이브 검증 → 붕괴 → 후퇴·재편 |
| [결과 양식](results/RESULT_TEMPLATE.md) | 구현 증거와 GPT 리뷰 기록 |

## GPT ↔ Claude Code 작업 흐름

1. GPT가 기획·요구사항·수용 기준을 문서와 WP에 기록한다.
2. Claude Code가 해당 WP의 의존성과 기술 결정을 확인하고 구현·테스트한다.
3. Claude Code가 코드, 변경 비교, 결과 문서를 같은 작업 브랜치에 기록한다.
4. GPT가 결과와 실제 변경을 검토해 PASS 또는 REVISE를 기록한다.
5. PASS 후 다음 WP를 시작한다. REVISE이면 같은 WP의 기준을 유지하며 보완한다.

첫 단계는 Git 문서를 통한 수동 핸드오프다. 이 저장소만으로 GPT나 Claude Code가 자동 실행되지는 않는다.

### Claude Code에 전달할 요청

```text
README.md, CLAUDE.md, docs/DECISIONS.md를 읽고 backlog/WP-001.md를 수행한다.
엔진과 실행 환경을 먼저 조사하고 기술 선택을 DECISIONS.md에 기록한다.
WP의 Scope만 구현하며 모든 Acceptance Criteria에 대해 증거를 남긴다.
실제 실행 화면과 재현 가능한 테스트 결과를 확인한다.
results/RESULT_TEMPLATE.md를 복사해 results/WP-001-RESULT.md에 결과를 기록한다.
구현 커밋과 기준 커밋, 변경 파일, 미해결 문제를 함께 전달한다.
```

### GPT에 전달할 리뷰 요청

```text
backlog/WP-001.md, results/WP-001-RESULT.md와 기록된 기준/구현 커밋의 diff를 검토한다.
게임 목표, 범위, 수용 기준, 실제 테스트 증거, 다음 WP 확장 가능성을 확인한다.
각 기준을 PASS / FAIL / NOT RUN으로 판정하고 최종 PASS 또는 REVISE를 결과 파일에 기록한다.
실패나 미실행 기준이 있으면 보완 작업을 명시한다. 증거 없이 통과시키지 않는다.
```

## 개발 시작 전

엔진·버전, 렌더링 방식, 대상 플랫폼, 성능 측정 장비는 미확정이다. 기존 대화의 Unity 언급은 구현 예시이며 엔진 확정으로 간주하지 않는다. WP-001의 기술 착수 단계에서 결정한다.

저장소는 비공개를 기본으로 한다. 참조 이미지와 원본 대화는 배포 파일에 포함하지 않는다. 상용 제목·출시 일정·라이선스는 미정이다.
