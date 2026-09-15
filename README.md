# 한양 디펜스 · Hanyang Defense

**한양 전체를 무기화하는 대규모 전투 디펜스.** 조선 사이버펑크 세계에서 적을 유도·압축하고 도시의 시설을 연결해 싸우는 로그라이트 디펜스 프로젝트입니다.

현재 단계는 **WP-001 DONE (2026-09-13) · WP-002 DONE (2026-09-14) · WP-003 DONE (GPT 재리뷰 PASS `f5d7e69`, 2026-09-15 — D-032 외곽 HP 360)** 이며 **WP-004 REVIEW (플레이 흐름·메뉴·재시작, 2026-09-16 구현·검증 완료, GPT 판정 대기)** 입니다. Godot 4.7 프로젝트로 실행 가능한 회색상자 프로토타입(1,000개체 · 세 경로 · 장승 병목 · 화차 집중 사격)과 헤드리스 테스트, 릴리스 빌드·성능 측정 절차가 있습니다. 자동 에이전트 연동은 없습니다.

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
| [GAME_GUIDE](docs/GAME_GUIDE.md) | 플레이어·테스터용 게임 가이드: 지도·적·시설·표적·봉수망·WP-003 런·조작·설정 (WP-001~003 기준) |
| [TEST_REPORT](results/TEST_REPORT.md) | WP-001~003 통합 테스트 리포트: 스위트 780건, AC 최종 판정, 시나리오, 성능, 화면 증거, 리뷰 이력 |
| [WP-004](backlog/WP-004.md) | 시작·일시정지·결과·재시작·설정 |
| [결과 양식](results/RESULT_TEMPLATE.md) | 구현 증거와 GPT 리뷰 기록 |
| [WP-001 결과](results/WP-001-RESULT.md) | WP-001 구현·검증 결과, AC별 증거, 성능 측정 |

## GPT ↔ Claude Code 작업 흐름

1. GPT가 기획·요구사항·수용 기준을 문서와 WP에 기록한다.
2. Claude Code가 해당 WP의 의존성과 기술 결정을 확인하고 구현·테스트한다.
3. Claude Code가 코드, 변경 비교, 결과 문서를 같은 작업 브랜치에 기록한다.
4. GPT가 결과와 실제 변경을 검토해 PASS 또는 REVISE를 기록한다.
5. PASS 후 다음 WP를 시작한다. REVISE이면 같은 WP의 기준을 유지하며 보완한다.

첫 단계는 Git 문서를 통한 수동 핸드오프다. 이 저장소만으로 GPT나 Claude Code가 자동 실행되지는 않는다.

### Claude Code에 전달할 구현 요청 (WP-004 READY)

```text
최신 main의 CLAUDE.md, GAME_DESIGN, SYSTEM_SPEC, DECISIONS와 backlog/WP-004.md를 읽는다.
wp/004-play-flow 브랜치에서 착수 기준 SHA를 기록하고 IN_PROGRESS로 전환한다.
시작·일시정지·확인·결과·설정 화면을 실제 전투와 연결한다.
진행 중 R은 재시작 확인으로, Esc/P는 일시정지로 변경한다.
메뉴 중 전투/배치 정지, 입력 관통 방지, 동일 초기 상태 재시작을 검증한다.
음향/효과 신설·재화·런 저장·전장 에셋 전체 교체는 포함하지 않는다.
기존 자동 perf/capture/headless 경로와 실제 모드별 존/시설을 보존한다.
AC-01~08, 두 해상도 실제 화면, 기존 회귀와 release 성능을 검증한다.
results/WP-004-RESULT.md에 기준/구현/증거 SHA, AC 판정, 실행 절차와 증거를 기록한다.
완료 후 REVIEW와 Draft PR로 GPT 리뷰를 요청한다. main에 직접 병합하지 않는다.
```

### GPT에 전달할 리뷰 요청 (구현 결과 검토 예시: WP-002)

```text
backlog/WP-002.md, results/WP-002-RESULT.md와 기록된 기준/구현 커밋의 diff를 검토한다.
게임 목표, 범위, 수용 기준, 실제 테스트 증거, 다음 WP 확장 가능성을 확인한다.
각 기준을 PASS / FAIL / NOT RUN으로 판정하고 최종 PASS 또는 REVISE를 결과 파일에 기록한다.
실패나 미실행 기준이 있으면 보완 작업을 명시한다. 증거 없이 통과시키지 않는다.
```

## 실행 환경 (WP-001에서 확정)

엔진은 **Godot 4.7.stable (GDScript, 2D 탑다운, gl_compatibility)** 이다. 근거와 성능 예산은 [DECISIONS D-007~D-011](docs/DECISIONS.md)에 있다. 기존 대화의 Unity 언급은 구현 예시였으며 채택하지 않았다.

### 설치

1. [Godot 4.7.stable](https://godotengine.org/download) 표준(비-.NET) 에디터를 받아 실행 파일을 `godot`이라는 이름으로 PATH에 둔다. 확인: `godot --version` → `4.7.stable.official.5b4e0cb0f`.
2. 릴리스 빌드를 만들려면 같은 버전의 **Windows export template**을 설치한다(에디터 → Editor → Manage Export Templates, 또는 `%APPDATA%\Godot\export_templates\4.7.stable\`).
3. 저장소를 체크아웃한다. 추가 패키지 설치는 없다. 최초 실행 시 Godot이 `.godot/` 캐시를 만든다(gitignore).

### 실행·테스트·빌드

```bash
# 플레이 (창 실행, 1920x1080 논리 해상도)
godot --path . --rendering-driver opengl3
```

```bash
# 헤드리스 자동 검증 (AC-01~06 대응, 종료 코드 0 = 전부 통과)
godot --headless --path . --script res://tests/run_tests.gd -- --report=results/evidence/test_report.txt
```

```bash
# 회색상자 지형·경로장 덤프 (ASCII)
godot --headless --path . --script res://game/tools/dump_map.gd
```

```bash
# 증거 캡처 (실제 실행 화면 PNG + 상태 JSON). ac01 / ac02 / ac06
godot --path . --rendering-driver opengl3 -- --capture=ac06 --out-dir=D:/abs/path/to/results/evidence/captures
```

```bash
# 릴리스 빌드 (export_presets.cfg 사용)
godot --headless --path . --export-release "Windows Desktop Release" build_out/windows/hanyang_defense_wp001.exe
```

```bash
# 성능 측정 (릴리스 빌드, 준비 10초 + 측정 60초, JSON 출력). 시나리오 move / combat
./build_out/windows/hanyang_defense_wp001.exe -- --perf --scenario=combat --warmup=10 --measure=60 --out=D:/abs/path/perf_combat.json
```

```bash
# P-007 측정: 포화 골목의 설치 성공률과 홀드 대기시간 (헤드리스, JSON 출력)
godot --headless --path . --script res://game/tools/probe_occupancy.gd -- --out=D:/abs/path/occupancy_probe.json
```

`--perf` 모드는 `benchmark_hold_alive`를 켜서 매 틱 끝에 동시 생존 수를 `target_alive`로 즉시 보충한다(D-009의 부하를 측정 프레임 전체에서 유지하기 위한 벤치마크 전용 규칙, 일반 플레이에서는 꺼져 있음). 결과 JSON의 `load_held_all_frames`가 true여야 부하 조건을 충족한 측정이다.

한 번에 전부 실행하려면 `scripts/verify.ps1`(Windows) 또는 `scripts/verify.sh`(Git Bash)를 사용한다. `verify.ps1`은 각 단계의 종료 코드·산출물·성능 합격 조건을 검사하고 실패 시 즉시 중단한다. 조작법과 명령행 옵션은 [game/scenes/main.gd](game/scenes/main.gd) 상단 주석, 밸런스·시드 설정값은 [game/core/config.gd](game/core/config.gd)에 있다. 기본 시드는 `20260913`.

### WP-002 봉수망 (2026-09-14)

기본 플레이는 **WP-002 모드**(`targeting_mode=wp002`: 화차는 로컬 100px + 같은 봉수망 그룹 센서의 탐지만 안다)와 **fixture B**(화차 4·봉수대 8·혼천의 4)로 시작한다. WP-001 검증 구성은 `--set=targeting_mode=wp001 --set=fixture=wp001`(테스트·캡처 `ac01/ac02/ac06`·성능 `move/combat`이 자동으로 고정)이다. 봉수대 연결 180px, 센서 탐지 140px, 화차 로컬 100px, 사거리 200px — 모두 `game/core/config.gd`.

```bash
# WP-002 fixture A 캡처: 비연결 → 연결(공유 사격) → 단절(오래된 표적 사격 없음) → 로컬 사격 → 복구
godot --path . --rendering-driver opengl3 -- --capture=wp002_a --out-dir=D:/abs/path/results/evidence/wp-002/captures
```

```bash
# WP-002 fixture B 성능 (16시설 + 1,000체). network_move / network_combat(B8 전환 12회 + 장승 (22,28) 12회)
.\scripts\perf_with_memory.ps1 -Scenario network_combat -Out results\evidence\wp-002\perf\perf_network_combat_1000_release.json
```

증거는 `results/evidence/wp-002/{tests,captures,perf}/`에 두고 WP-001 증거는 보존한다. `scripts/verify.*`가 WP-001 단계에 이어 4b(fixture A 캡처)·6b(fixture B 성능, 계약 검사 포함)를 실행한다.

### WP-003 검증·붕괴·후퇴·재편 (2026-09-15)

기본 플레이는 이제 **WP-003 런**(`Config.for_wp003()`: fixture C = fixture B 16 + 외곽 장승 2, 10존, 사격 후 도달 처리, 유한 3웨이브 1,140체, 외곽 HP 360(D-032, READY v1.0의 120은 GPT 리뷰로 대체) / 핵심 HP 60)이다. 외곽 거점 (47,26)이 HP 0이 되면 한 번 붕괴: 화차·중영이 회수 대기로 빠지고 나머지 외곽 시설은 비활성(점유·장승 차단 유지), 목표가 핵심 (47,10)으로 바뀐다. 플레이어는 내곽(노란 테두리)의 빈 칸을 클릭해 회수 화차 1대를 배치한다(`R` 재시작). WP-001/002 구성은 `Config.for_wp001()` / `Config.new()`(sandbox)로 보존된다.

```bash
# F1 정상 방어 타임라인 (헤드리스, 초 단위 장부 + 이벤트 JSON)
godot --headless --path . --script res://game/tools/wp003_timeline.gd -- --out=D:/abs/path/results/evidence/wp-003/tests/f1_timeline.json
```

```bash
# F2 캡처: 외곽 방어 → 20초 강제 붕괴(실제 도달 피해) → 무효/유효 미리보기 → 25초 회수 배치 B → 내곽 사격 → 종료
godot --path . --rendering-driver opengl3 -- --capture=wp003_f2 --out-dir=D:/abs/path/results/evidence/wp-003/captures
```

```bash
# D-027 전환 성능: collapse_move / collapse_combat (18시설·10존·1,000체 유지, 측정 20초 붕괴·25초 배치, 핵심 무적·기록)
.\scripts\perf_with_memory.ps1 -Scenario collapse_combat -Out results\evidence\wp-003\perf\perf_collapse_combat_1000_release.json
```

```bash
# F3 통제 A/B 비교: 헤드리스 개체별 장부(JSON) + 실제 화면 캡처(A: 비연결, B: B2 부착)
godot --headless --path . --script res://game/tools/wp003_f3_evidence.gd -- --out=D:/abs/path/results/evidence/wp-003/tests/f3_ab.json
godot --path . --rendering-driver opengl3 -- --capture=wp003_f3b --out-dir=D:/abs/path/results/evidence/wp-003/captures
```

증거는 `results/evidence/wp-003/{tests,captures,perf}/`. `scripts/verify.*`가 4c(F1 타임라인·F3 A/B 장부·F2/F3 캡처)·6c(전환 성능, D-027 계약 검사 + 구간 프레임 완전 매핑·실행파일 SHA-256)를 추가로 실행한다. `.\scriptserify.ps1 -Wp003`은 승인된 WP-001/002 증거를 건드리지 않고 WP-003 증거만 재생성한다. 테스트 스위트(WP-001/002 회귀 + WP-003 + 실제 scene 진입 경로)는 종료 코드 0이어야 한다.

### WP-004 플레이 흐름·메뉴·재시작 (2026-09-16)

일반 실행은 **시작 화면(TITLE)** 에서 시작한다(게임 시작 / 설정 / 종료). 전투 중 `Esc`/`P` 또는 우상단 버튼이 **일시정지 메뉴**(계속하기 / 설정 / 다시 시작 / 시작 화면으로)를 열고, 메뉴가 열려 있는 동안 전투·배치·웨이브 타이머는 완전히 멈춘다(재개 시 몰아 처리 없음). 진행 중 `R`과 메뉴의 다시 시작·시작 화면 복귀는 **확인창**을 거치며(기본 포커스 취소), 승패가 확정되면 **결과 화면**(플레이 시간·도달 웨이브·처치·거점 도달·외곽 결과·회수 화차·재배치 위치·핵심 HP)이 뜨고 다시 시작(`R`)·시작 화면은 확인 없이 즉시다. 재시작은 같은 시드·초기 데이터의 새 런이며 이전 런의 입력·일시정지·결과는 무효다. `Esc`는 한 단계만 닫고, 종료는 TITLE의 종료 버튼뿐이다. 설정(창 모드/전체화면)은 즉시 적용되어 `user://settings.cfg`에 저장되며(`--settings=<경로>`로 대체 가능) 파일이 없거나 깨져 있으면 기본값으로 시작한다. `--perf`/`--capture`/헤드리스 도구는 메뉴와 설정 파일을 우회한다(`--capture=wp004_ui|wp004_ui_720`만 메뉴를 실제로 조작해 캡처).

```bash
# WP-004 메뉴 흐름 캡처 (1920x1080 / 1280x720): TITLE → 설정 → 전투 → 일시정지 → 설정 → 확인창 → 결과(패배/승리) → TITLE
godot --path . --rendering-driver opengl3 -- --capture=wp004_ui --out-dir=D:/abs/path/results/evidence/wp-004/captures --settings=D:/abs/path/results/evidence/wp-004/captures/settings_capture.cfg
```

`scripts/verify.*`가 4d(WP-004 캡처 2종, 상태 전이 로그 검사)를 추가로 실행하고 `.\scripts\verify.ps1 -Wp004`는 WP-003 승인 증거를 건드리지 않고 WP-004 캡처와 새 release의 collapse 성능(`results/evidence/wp-004/perf/`)을 만든다.

### 조작

WP-003 런: `LMB` 회수 화차 배치(내곽만, 누르고 있으면 셀이 빌 때까지 재시도; 메뉴를 열거나 재시작하면 누르고 있던 입력은 버려짐) · `Esc`/`P` 일시정지 메뉴 · `R` 재시작 확인창(결과 화면에서는 즉시 재시작) · `D` 상세 패널(경로·밀도·화차·봉수망, 좌하단) 접기 · `Z/G/H/F12` 동일 · 자유 설치/철거/`T`/`C`는 비활성. HUD는 좌상단(런 상태·HP·회수 안내·조작)과 좌하단(상세)으로 나뉘어 내곽·핵심 시설을 가리지 않는다. 시설에 커서를 올리면 정보 패널. 아래는 WP-001/002 sandbox 조작(`--set=run_mode=sandbox --set=fixture=b` 등).

`LMB` 설치(누르고 있으면 셀이 빌 때까지 재시도) · `RMB` 제거 · `1/2/3/4` 장승/화차/봉수대/혼천의 모드 · `T` 커서 아래 시설 활성/비활성 전환(디버그 파괴·수리) · 시설에 커서를 올리면 부착 봉수대·그룹·로컬/공유 인지 수·표적 출처·대기 이유 패널 표시 · `C` 전투 토글(처치 끔) · `Z` 밀도 존 표시 · `G` 사거리/탐지/연결 반경 · `Esc`/`P` 일시정지 메뉴 · `R` 초기화 확인창(같은 시드, 망·부착·표적 초기화 후 fixture 복원) · `H` HUD · `F12` 캡처(`%APPDATA%\Godot\app_userdata\...\captures`) · 종료는 시작 화면의 종료 버튼

## 공개 범위와 권리

저장소는 **공개(Public)** 다 (2026-09-13 사용자 요청, [D-010](docs/DECISIONS.md)). `docs/art/`의 이미지는 AI 생성 기획 참고 자료이며 실제 실행 화면이 아니다. 원본 대화·제삼자 에셋·폰트는 포함하지 않는다. HUD 한글은 Godot의 시스템 폰트 폴백으로 표시된다. 상용 제목·출시 일정·라이선스는 미정이다.

## 비주얼 기획

### 예상 플레이 화면

![예상 플레이 화면: 세 진입로, 포졸, 화차와 봉수망, 건설 위치 및 HUD](docs/art/hanyang-defense-gameplay-mockup-01.png)

실제 실행 화면이 아닌 AI 생성 목업이다. 카메라·적 크기·경로·시설 배치의 가독성을 검토한다. 봉수망과 자원 HUD는 완성형 방향을 보여주며 WP-001의 구현 범위를 추가하지 않는다.

### 콘셉트 아트

![콘셉트 아트: 한양 방어망과 대규모 요괴 침입](docs/art/hanyang-defense-concept-01.png)

조선 건축, 청동 병기, 장승과 봉수망의 분위기를 위한 AI 생성 콘셉트다. 실제 게임 카메라와 성능 목표를 표현한 화면은 아니다.

이미지별 용도와 구현 시 해석은 [비주얼 레퍼런스](docs/art/README.md)를 참고한다.
