# Orca 유령 pane reap — UI에서 닫혔지만 claude가 살아있는 pane의 자동 정리

- 날짜: 2026-08-19
- 상태: 채택
- 관련: `2026-08-orca-dead-pane-sweep.md`(dead pane reap/nudge),
  `2026-08-orca-resume-config-dir.md`(교차 계정 resume),
  `claude/skills/orca-relay/SKILL.md`(진단 플레이북)

## 맥락

"비어있는 main을 클릭하면 이전 세션이 강제로 `claude --resume` 되고, 로컬·원격
어디서도 세션을 닫을 수 없다"는 보고를 조사한 결과 (2026-08-19, upstage 원격
서버 실측):

1. **UI 닫기는 서버 프로세스를 죽이지 않는다.** tab을 닫으면 원장
   (`~/.orca/sessions/<ns>.json`)에서 tab만 제거되고, relay가 쥔 pane 셸과 그
   안의 claude는 계속 산다. solly 워크트리에서 이런 "유령 pane"이 3개 발견됐고,
   그중 하나는 PR 머지 후 삭제된 worktree 디렉토리 안에서 2시간 가까이
   waiting 상태였다.
2. **resume 명령의 출처는 원장이 아니라 ai-vault다.** relay 자식
   `relay-ai-vault-service.js`가 transcript(`projects/*/**.jsonl`)를 스캔해
   세션 목록과 `resumeCommand`(`claude --resume <id>`)를 조립한다. 원장의 해당
   워크트리 tab 목록이 비어 있어도, relay가 "tab 없는 활성 agent pane"을
   기억하는 동안 앱은 프로젝트를 열 때마다 **새 PTY를 만들어 resumeCommand를
   자동 타이핑**한다 — 실제로 클릭 시각(18:57:39)에 새 pane 셸이 생성되고
   그 안에서 resume이 실행되는 것을 확인했다.
3. 따라서 자기강화 루프가 된다: 닫아도 claude가 살아 훅 이벤트를 계속 보냄 →
   relay/앱이 활성 agent로 인식 → 프로젝트 열 때마다 같은 세션을 또 resume →
   fork된 claude가 하나 더 생김(17:13 → 18:41 → 18:57 pane 누적으로 재현 확인).
   부수 피해로 같은 세션 transcript가 cwd별 프로젝트 디렉토리에 복제되고
   subagent transcript 트리가 사이드바에 계속 불어난다.
4. 기존 `--sweep`의 reap은 "서브트리에 셸 외 프로세스 없음"을 요구하므로
   (동 결정 기록), **살아있는 claude를 문 유령 pane은 구조적으로 영원히
   정리되지 않는다** — 이것이 사각지대였다.

## 결정

`orca-nudge --sweep`에 ghost reap 단계를 추가한다: 원장이 대표성 검증을 통과한
상태에서 tab이 없는데 claude가 살아있는 pane은, 아래 가드를 전부 통과할 때만
claude에 SIGTERM을 보낸다. claude가 종료되면 pane은 dead pane이 되어 기존
reap 단계가 셸까지 회수한다.

가드 (전부 충족해야 발사):

- claude가 `sessions/<pid>.json`으로 **idle 또는 waiting**을 자기보고
  (busy/working은 절대 건드리지 않음; 전송 직전 재확인). waiting을 포함하는
  이유: tab이 사라진 pane의 승인 프롬프트는 사용자가 응답할 방법 자체가 없다.
- claude 나이 ≥ `ORCA_NUDGE_GHOST_MIN_AGE`(기본 900초), pane 셸 나이 ≥
  `ORCA_NUDGE_REAP_MIN_AGE`(기본 600초).
- **tab 부재의 이중 관측**: 첫 관측에서 marker만 남기고, marker 나이 ≥
  `ORCA_NUDGE_GHOST_CONFIRM`(기본 600초)인 두 번째 관측에서만 발사. 원장
  기록이 pane 생성보다 늦는 경우(새 pane의 store write 지연)를 배제한다.
- TERM 후 `GHOST_RETERM_SEC`(300초) 동안 재전송하지 않아 claude의 정상 종료
  (상태 저장)를 기다린다. marker는 대상 claude PID에 묶여 있어 새 claude가
  뜨면 자동 무효화된다.

TERM은 데이터를 지우지 않는다: transcript는 디스크에 남고 세션은 언제든 수동
`--resume` 가능하다.

## 검토한 대안

- **자동 resume 자체를 끄기** — resume 타이핑은 데스크톱 앱의 동작이라 서버
  쪽(harness)에서 제어할 수단이 없다. 근본 해결은 업스트림 몫: "UI 닫기 시
  서버 프로세스 종료"와 "닫힌 pane 자동 resume 중단"을 보고 후보로 남긴다.
- **nudge로 해결** — nudge는 relay 상태만 리셋할 뿐 프로세스를 없애지 못하고,
  유령 pane의 본질은 살아있는 claude이므로 무의미하다.
- **수동 kill 안내만 유지** — 이번 조사처럼 매번 프로세스 트리를 뒤져야 하고,
  cron 없이는 재발을 못 막는다.
- **idle만 kill (waiting 제외)** — 삭제된 worktree에서 waiting으로 2시간 방치된
  실측 사례가 반증. tab 없는 waiting은 영원히 응답 불가능한 상태다.

## 결과

- UI에서 세션을 닫으면 (idle 기준) 최대 ~25분 안에 서버 claude까지 실제로
  종료되고, "빈 main 클릭 → 강제 resume" 루프의 미끼가 사라진다.
- 수용한 위험: 원장이 10분 이상 실제 UI 상태보다 뒤처지는 비정상 상황에서는
  화면에 보이는 idle 세션이 종료될 수 있다. 이중 관측 + 대표성 검증으로
  좁혔고, 종료돼도 transcript가 남아 resume으로 복구된다.
- 검증: 격리 픽스처(가짜 relay pane/claude/원장) 단위 테스트로 confirm 창
  준수, busy 가드, 건강한 pane 불간섭, marker 수명, 원장 불신 시 전면 보류를
  확인 (2026-08-19).
