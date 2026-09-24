# 시설 ID 범례 — 라벨 숨김 캡처

기준: wp005_sample_log.json의 after_collapse 상태. 1080p 논리 좌표이며 720p에서는 2/3배다. 회수된 화차는 전장 목록에서 빠져 우상단 노란 대기 슬롯에 표시된다.

| ID | 이름 | 종류 | 중심(px) | 활성 |
|---|---|---|---|---|
| 2 | 화차·서영 | HWACHA | 620, 520 | False |
| 3 | 화차·동영 | HWACHA | 1300, 520 | False |
| 4 | 화차·궁성 | HWACHA | 940, 360 | True |
| 5 | 봉수 B1 | BONGSU | 700, 440 | False |
| 6 | 봉수 B2 | BONGSU | 860, 440 | True |
| 7 | 봉수 B3 | BONGSU | 1020, 440 | True |
| 8 | 봉수 B4 | BONGSU | 1180, 440 | False |
| 9 | 봉수 B5 | BONGSU | 700, 600 | False |
| 10 | 봉수 B6 | BONGSU | 860, 600 | False |
| 11 | 봉수 B7 | BONGSU | 1180, 600 | False |
| 12 | 봉수 B8 | BONGSU | 900, 680 | False |
| 13 | 혼천의 S1 | SENSOR | 620, 560 | False |
| 14 | 혼천의 S2 | SENSOR | 1260, 560 | False |
| 15 | 혼천의 S3 | SENSOR | 900, 800 | False |
| 16 | 혼천의 S4 | SENSOR | 960, 320 | True |
| 17 | 장승 J1 | JANGSEUNG | 900, 740 | False |
| 18 | 장승 J2 | JANGSEUNG | 460, 500 | False |

## 화면 확인

- 붕괴 전: `wp005_sample_a_dense_t15.png`.
- 붕괴 후: `wp005_sample_b_collapse_t20.5.png`. 봉수 연결2/단절6, 화차 기본1/비활성3(회수 슬롯1 포함), 장승 비활성2, 혼천의 활성1/비활성3이 실제 sprite draw 장부와 일치한다.
- 재배치 후: `wp005_sample_e_recovery_placed_t25.5.png`.
- 같은 이름의 `_720_` 캡처는 1280×720 결과다.
- 연결/단절은 봉수 등불의 청록 점등, 비활성 화차·장승·혼천의는 저채도와 소등으로 구분한다. 시설 종류의 실루엣은 유지한다.
- 작은 크기에서 소등 대비가 약한 점과 아직 없는 발사/거점/경계 그림은 후속 보정 대상이다.
