# 2026-08 — Clawd on Desk 훅을 harness가 소유하고, Clawd 자동 관리는 끈다

## 상태

확정 (2026-08-23). [Clawd on Desk](https://github.com/rullerzhou-afk/clawd-on-desk) 0.15.0 기준.
Claude Code 세션 상태를 로컬 데스크톱 Clawd로 보내는 훅을 **harness의 `claude/settings.json`에
직접 선언**하고, 실제 실행은 `claude/hooks/clawd-relay.sh` 래퍼가 런타임에 분기한다.
Clawd 앱의 Claude hook 자동 관리(`manageClaudeHooksAutomatically`)는 **반드시 꺼 둔다**.

## 배경

Clawd는 Claude Code 훅(SessionStart/PreToolUse/Stop 등)으로 세션 상태를 받아 데스크톱 펫 애니메이션,
세션 Dashboard, 권한 버블을 띄운다. 원격 SSH 서버의 세션은 `Settings → Remote SSH → Deploy / Repair Hooks`가
서버의 `~/.claude/hooks/`에 런타임 파일(`clawd-hook.js`, `clawd-remote.json` 등)을 복사하고
`~/.claude/settings.json`에 훅을 등록한 뒤, `ssh -R` 리버스 터널(기본 23333)로 로컬 Clawd에 중계한다.

이 harness 환경과 세 지점에서 충돌했다.

1. **`~/.claude`만 본다.** 원격 배포 레이아웃(`src/remote-ssh-layout.js`)은 `$HOME/.claude`를
   하드코딩하고 `CLAUDE_CONFIG_DIR`을 읽지 않는다. 업무 계정(`ccu`, `~/.claude-upstage`)은
   훅을 얻지 못해 세션이 인식되지 않는다 — [Orca 때와 같은 문제](2026-08-orca-agent-hooks.md).
2. **symlink를 깨뜨린다.** Clawd는 `settings.json`을 임시 파일 → `rename()`으로 교체한다
   (`hooks/json-utils.js`). symlink를 따라가지 않으므로 `~/.claude/settings.json`이 레포 파일과
   분리된 일반 파일이 된다. 실제로 2026-08-23 서버 배포 6분 뒤 `./setup.sh`가 symlink를 복원하면서
   Clawd 훅이 전부 사라졌다(`~/.claude/settings.json.bak`에만 남음).
3. **자기 훅을 덮어쓴다.** 로컬 Clawd 앱은 시작 시·파일 변경 감시·주기 점검마다 `settings.json`을
   재동기화하며, 커맨드에 `clawd-hook.js` 문자열이 있는 항목을 찾아 **자신이 기대하는 절대경로 형태로
   command를 되돌린다**(`hooks/install.js` `syncCommandHook`). 레포에 변수화된 항목을 넣어도
   Clawd가 켜지는 순간 `/usr/local/bin/node "/Applications/Clawd on Desk.app/…"`로 덮이고,
   그 쓰기가 2번의 rename이라 symlink가 다시 깨진다 → `setup.sh` ↔ Clawd 무한 핑퐁.

## 결정

- `claude/hooks/clawd-relay.sh <Event>` 래퍼를 두고, `claude/settings.json`의 12개 이벤트
  (SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Stop,
  SubagentStart, SubagentStop, Notification, Elicitation, PermissionRequest)에서 이 래퍼만 호출한다.
  - 커맨드에 `clawd-hook.js` 리터럴을 넣지 않는다. Clawd의 소유권 판정 마커가 이 문자열이라,
    없으면 Clawd는 이 항목을 자기 것으로 인식하지도, 덮어쓰지도 않는다.
  - 래퍼는 `$HOME/.claude/hooks/clawd-remote.json`이 있으면 **remote 모드**(Clawd가 배포한 env 변수
    세트로 `clawd-hook.js` 실행), macOS에 앱 번들이 있으면 **local 모드**, 둘 다 없으면 stdin을 비우고
    조용히 `exit 0`. 머신마다 다른 절대경로(nvm node, 앱 번들)는 런타임에 찾는다.
  - `PermissionRequest`는 Clawd의 `http` 훅을 curl로 재현한다: stdin JSON을 `/permission`(local)
    또는 `/permission/<routingNonce>`(remote, 식별 파일에서 읽음)로 POST하고 응답 본문을 그대로 stdout에
    낸다. Claude Code는 http 훅과 command 훅의 출력 스키마가 같으므로 동등하게 동작한다.
    실패·타임아웃이면 출력 없음 → 터미널 기본 프롬프트로 fallback. 타임아웃은 Clawd 기본 600s 대신
    120s(`timeout`) / curl 110s로 줄였다. 원격 식별 파일의 nonce는 프로필마다 달라 레포에 넣지 않는다.
  - 상태 이벤트는 모두 `async: true`, `timeout: 10` — 응답을 기다리지 않고, Clawd 부재 시 즉시 종료.
- 로컬 Clawd 앱: `Settings → Agents → Claude Code → 자동 관리 끄기`("자동 관리만 끄기" 선택.
  "끄고 설치된 hooks 제거"는 파일을 다시 써서 symlink를 깨뜨릴 수 있다).
- 원격 서버: **`Deploy / Repair Hooks`를 다시 누르지 않는다.** 누르면 `~/.claude/settings.json`을
  rename으로 다시 써서 symlink가 깨지고 `clawd-hook.js` 리터럴 항목이 중복 추가된다.
  런타임 파일이 이미 있으므로 `Connect`만 쓴다. 재배포가 꼭 필요하면(nonce 교체, Clawd 업그레이드로
  훅 파일 갱신) 배포 직후 `./setup.sh && ./check.sh`로 복원한다 — 식별 파일은 `~/.claude/hooks/`에
  남으므로 래퍼가 새 nonce를 자동으로 읽는다.
- `check.sh`: `clawd-relay.sh` 등록 확인, 레포 `settings.json`에 `clawd-hook.js` 리터럴이 생기면
  오류(자동 관리가 다시 켜졌다는 신호), 런타임 배포 여부는 info로 표시.

## 고려했으나 채택하지 않은 것

- **Clawd가 쓴 항목을 그대로 레포에 복사**: `clawd-hook.js` 마커 때문에 Clawd가 덮어쓰고,
  사용자명·nvm·앱 번들 절대경로가 박혀 portable 규칙에도 어긋난다.
- **`CLAUDE_CONFIG_DIR=~/.claude-upstage`로 Clawd 원격 배포**: 레이아웃이 env를 무시하므로 불가능하고,
  가능하더라도 symlink가 깨진다.
- **`profile-isolated` 실험 런타임**(`CLAWD_ENABLE_EXPERIMENTAL_REMOTE_ISOLATION=1`): 계정별
  config root를 새로 만들어 harness의 symlink 구조와 아예 맞지 않는다. 미채택.
- **`PermissionRequest` 제외(상태 훅만)**: 사이드 이펙트가 가장 작지만, 권한 버블이 Clawd를 쓰는
  핵심 이유라 포함하되 타임아웃을 줄이는 쪽을 택했다.

## 영향 / 운영

- 두 계정(`cc`, `ccu`)이 같은 `settings.json`을 symlink하므로 양쪽 세션 모두 Clawd에 보고된다.
  Dashboard에서 원격 세션은 프로필 Host prefix(예: `aimp`)로 구분된다.
- Clawd가 배포되지 않은 머신에서는 훅이 프로세스 하나(bash) 뜨고 바로 끝난다.
- **Clawd 업그레이드 시 확인할 것**: `hooks/install.js`가 만드는 remote 커맨드의 env 변수 세트
  (`CLAWD_REMOTE`, `CLAWD_SSH_REMOTE`, `CLAWD_REMOTE_IDENTITY_PATH`, `CLAWD_SSH_SECURE_MARKER_PATH`,
  `CLAWD_HOST_PREFIX_PATH`, `CLAWD_REMOTE_LAST_LOG_PATH`, `CLAWD_STATUSLINE_SIDECAR_PATH`),
  `EVENT_TO_STATE`의 이벤트 목록, `/permission` 경로 규칙, `CLAUDE_STATE_HOOK_MARKER`(`clawd-hook.js`).
  바뀌면 `clawd-relay.sh`만 고치면 된다. 비교용 원본은 `~/.claude/settings.json.bak`(2026-08-23)과
  Clawd 레포의 `hooks/install.js` `buildCommandHookSpec`.
- 진단: `~/.clawd/remote-last-error.log`(원격 훅 실패), 서버에서 `ss -ltnp | grep 23333`(터널),
  Clawd Doctor의 `ingressRejectedCount`(nonce 불일치).
