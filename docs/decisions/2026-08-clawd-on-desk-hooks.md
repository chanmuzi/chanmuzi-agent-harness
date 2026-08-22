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
2. **레포 원본을 직접 덮어쓴다.** Clawd는 `settings.json`을 임시 파일 → `rename()`으로 교체하는데,
   0.15.0은 쓰기 전에 `resolveWritePath()`가 `fs.realpathSync`로 **symlink를 따라간다**
   (`hooks/install.js`). 즉 symlink는 유지되지만 rename 대상이 harness 레포의 `claude/settings.json`
   원본이 되어, git 추적 파일에 머신 절대경로가 박힌 훅이 주입된다(로컬에서 `M claude/settings.json`
   +188줄로 관측). 서버에서는 당시 `~/.claude/settings.json`이 이미 symlink가 아닌 일반 파일이어서
   그 파일에 주입됐고, 6분 뒤 `./setup.sh`가 symlink를 복원하면서 훅이 통째로 사라졌다
   (`~/.claude/settings.json.bak`에만 남음). 어느 쪽이든 harness 소유권 밖에서 파일이 바뀐다.
3. **자기 훅을 덮어쓴다.** 로컬 Clawd 앱은 시작 시·파일 변경 감시·주기 점검마다 `settings.json`을
   재동기화하며, 커맨드에 `clawd-hook.js` 문자열이 있는 항목을 찾아 **자신이 기대하는 절대경로 형태로
   command를 되돌린다**(`hooks/install.js` `syncCommandHook`). 레포에 변수화된 항목을 넣어도
   Clawd가 켜지는 순간 `/usr/local/bin/node "/Applications/Clawd on Desk.app/…"`로 덮이고,
   그 쓰기가 2번 경로로 레포 원본을 오염시킨다 → 레포 드리프트 ↔ Clawd 재주입 무한 핑퐁.

## 결정

- `claude/hooks/clawd-relay.sh <Event>` 래퍼를 두고, `claude/settings.json`의 15개 이벤트
  (SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Stop,
  StopFailure, PreCompact, PostCompact, SubagentStart, SubagentStop, Notification, Elicitation,
  PermissionRequest)에서 이 래퍼만 호출한다. 목록은 Clawd 설치기의 `CORE_HOOKS` + `VERSIONED_HOOKS`
  (Claude ≥2.1.78에서 전부 활성) + http 훅 1개와 동일하다. `--mode`를 주면 판정 결과
  (`remote|local|none`)만 출력하며 `check.sh`가 이를 사용한다 — 배포 감지 규칙의 단일 소유자는 래퍼다.
  - 커맨드에 `clawd-hook.js` 리터럴을 넣지 않는다. Clawd의 소유권 판정 마커가 이 문자열이라,
    없으면 Clawd는 이 항목을 자기 것으로 인식하지도, 덮어쓰지도 않는다.
  - 래퍼는 `$HOME/.claude/hooks/clawd-remote.json`이 있으면 **remote 모드**(Clawd가 배포한 env 변수
    세트로 `clawd-hook.js` 실행), macOS에 앱 번들이 있으면 **local 모드**, 둘 다 없으면 stdin을 비우고
    조용히 `exit 0`. 머신마다 다른 절대경로(nvm node, 앱 번들)는 런타임에 찾는다.
  - `PermissionRequest`는 Clawd의 `http` 훅을 curl로 재현한다: stdin JSON을 `/permission`(local,
    포트는 `~/.clawd/runtime.json`의 `port` 우선·23333 fallback — Clawd는 23333이 점유되면 23334~23337로
    옮긴다) 또는 `/permission/<routingNonce>`(remote, 식별 파일에서 읽음)로 POST하고 응답 본문을 stdout에
    낸다. Claude Code는 http 훅과 command 훅의 출력 스키마가 같으므로 동등하게 동작한다.
    파일에서 읽은 값은 jq로 파싱하고(port 숫자, nonce `[a-f0-9]{32}` 검증), 응답은
    `decision` 필드가 있는 JSON일 때만 전달한다. 실패·타임아웃이면 출력 없음 → 터미널 기본 프롬프트로
    fallback. 타임아웃은 Clawd 기본 600s 대신 120s(`timeout`) / curl 110s로 줄였다(`CLAWD_PERMISSION_TIMEOUT`로
    조정 가능). 원격 식별 파일의 nonce는 프로필마다 달라 레포에 넣지 않는다.
  - 상태 이벤트는 모두 `async: true`, `timeout: 10` — 응답을 기다리지 않고, Clawd 부재 시 즉시 종료.
- 로컬 Clawd 앱: `Settings → Agents → Claude Code → 자동 관리 끄기`("자동 관리만 끄기" 선택.
  "끄고 설치된 hooks 제거"는 파일을 다시 써서 symlink를 깨뜨릴 수 있다).
- 원격 서버: **`Deploy / Repair Hooks`를 다시 누르지 않는다.** 누르면 `~/.claude/settings.json`을
  rename으로 다시 써서 symlink가 깨지고 `clawd-hook.js` 리터럴 항목이 중복 추가된다.
  런타임 파일이 이미 있으므로 `Connect`만 쓴다. 재배포가 꼭 필요하면(nonce 교체, Clawd 업그레이드로
  훅 파일 갱신) 배포 직후 **`git status`로 `claude/settings.json` 오염을 확인하고
  `git checkout claude/settings.json`으로 되돌린 뒤** `./setup.sh && ./check.sh`를 돌린다 — 식별 파일은
  `~/.claude/hooks/`에 남으므로 래퍼가 새 nonce를 자동으로 읽는다.
- `check.sh`: `clawd-relay.sh` 등록 확인, 레포 `settings.json`에 `clawd-hook.js` 리터럴이 생기면
  오류(Clawd가 symlink를 따라 레포 원본에 재주입했다는 신호), 런타임 배포 여부는 `clawd-relay.sh --mode`
  결과로 표시.

## 고려했으나 채택하지 않은 것

- **Clawd가 쓴 항목을 그대로 레포에 복사**: `clawd-hook.js` 마커 때문에 Clawd가 덮어쓰고,
  사용자명·nvm·앱 번들 절대경로가 박혀 portable 규칙에도 어긋난다.
- **`CLAUDE_CONFIG_DIR=~/.claude-upstage`로 Clawd 원격 배포**: 레이아웃이 env를 무시하므로 불가능하고,
  가능하더라도 symlink가 깨진다.
- **`profile-isolated` 실험 런타임**(`CLAWD_ENABLE_EXPERIMENTAL_REMOTE_ISOLATION=1`): 계정별
  config root를 새로 만들어 harness의 symlink 구조와 아예 맞지 않는다. 미채택.
- **`PermissionRequest` 제외(상태 훅만)**: 사이드 이펙트가 가장 작지만, 권한 버블이 Clawd를 쓰는
  핵심 이유라 포함하되 타임아웃을 줄이는 쪽을 택했다.

## 알려진 잔존 위험

- **공유 호스트의 loopback 포트.** 원격 서버의 `127.0.0.1:<port>`는 같은 머신의 모든 사용자가 바인드할 수
  있다. 다른 로컬 사용자가 `ssh -R` 터널보다 먼저 그 포트를 잡으면 터널은 실패하고(Clawd 프로필에
  포트 충돌로 표시됨) 그 사이 훅 페이로드와 nonce가 그쪽으로 갈 수 있다. `ss -ltnp`로 리스너 소유자를
  확인하는 방어는 불가능하다 — 정상 `ssh -R` 리스너도 sshd 소유라 사용자 프로세스 정보가 없다(서버에서
  확인). 완화: 응답을 `decision` 필드가 있는 JSON으로 제한, `defaultMode: bypassPermissions`라
  `PermissionRequest` 자체가 드묾. 근본 해결(UNIX 소켓 등)은 Clawd 업스트림 몫이다.
- **half-open 대기.** 터널은 살아 있는데 로컬 Clawd가 응답하지 못하면(랩탑 sleep, 앱 종료 후 터널 잔존)
  권한 요청마다 curl `--max-time`(110s)까지 멈춘다. 버블 승인 대기가 설계 목적이라 더 줄이지 않았다.
  불편하면 `CLAWD_PERMISSION_TIMEOUT`로 조정.

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
