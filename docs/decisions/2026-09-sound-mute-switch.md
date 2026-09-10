# 2026-09 — 알림 사운드는 per-user 뮤트 스위치로 끄고, 훅 항목은 유지한다

## 상태

채택 (2026-09-10)

## 맥락

이 harness는 Claude Code의 `Stop` / `SubagentStop` / `PermissionRequest`(및 `Notification`)와
Codex의 `notify`에서 소리를 내는 훅을 `claude/settings.json`, `codex/config.toml`에 등록한다.
소리를 끄는 스위치가 없어서, 조용히 쓰고 싶은 머신·계정은 다음 중 하나를 골라야 했다:

- 훅 항목을 `claude/settings.json`에서 삭제 → 리포 추적 파일 변경. 커밋하면 모든 머신이
  무음이 되고, 커밋하지 않으면 Runtime Drift 규칙에 따라 stash/discard되어 `git pull` 때 되살아난다
- `disableAllHooks` → Orca·Clawd relay·git 가드 훅까지 함께 죽는다
- `settings.local.json` → 훅은 파일 간 병합만 되고 상위 훅을 제거할 수 없다

또 `claude/hooks/notification-sound.sh`만 `afplay`를 직접 호출하고 있어서 `play_sound()`에
스위치를 달아도 권한 요청 소리는 빠져나갔다.

## 결정

- `shared/lib/os.sh`에 `harness_sound_muted()`를 추가하고 `play_sound()` 첫 줄에서 검사한다.
  다음 중 하나면 무음:
  - 환경변수 `CHANMUZI_HARNESS_SILENT`가 비어 있지 않고 `0`이 아닐 때
  - 마커 파일 `${XDG_CONFIG_HOME:-$HOME/.config}/chanmuzi-agent-harness/mute-sounds`가 존재할 때
- 마커 파일이 기본 방식이다. 환경변수는 셸 rc를 거치지 않는 실행 경로(Orca resume, 데스크톱 앱,
  SSH 비로그인 셸)에서 전달이 보장되지 않지만, 파일은 어느 경로에서든 같은 홈을 보기 때문이다.
  환경변수는 한 세션·한 명령만 잠깐 끄거나 켤 때 쓴다.
- 스위치 상태는 리포 밖에 산다. 모델·테마와 같은 런타임 취향이므로 관리 config에 커밋하지
  않는다(Repository Rules).
- 모든 사운드 훅은 `play_sound()`를 거친다. `notification-sound.sh`도 `os.sh`를 source하고
  `play_sound`로 교체했으며, `check.sh`가 4개 훅 모두 `play_sound`를 호출하는지 검사한다.
- 훅 항목 자체는 `claude/settings.json`에 그대로 둔다. 소리를 다시 켜는 것은 마커 파일 삭제
  한 번이며, 훅 구성은 모든 머신에서 동일하게 유지된다.

## 사용법

```bash
# 끄기
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/chanmuzi-agent-harness"
touch "${XDG_CONFIG_HOME:-$HOME/.config}/chanmuzi-agent-harness/mute-sounds"
# 켜기
rm "${XDG_CONFIG_HOME:-$HOME/.config}/chanmuzi-agent-harness/mute-sounds"
# 이번 명령만 무음
CHANMUZI_HARNESS_SILENT=1 claude
```

실행 중인 세션을 재시작할 필요는 없다. 훅은 매번 새 프로세스로 뜨며 그때 파일을 확인한다.

## 검토한 대안

- **훅 항목 삭제 PR**: 모든 머신·계정이 무음이 되고, 다시 켜려면 또 PR이 필요하다. 취향을
  리포에 고정하는 셈이라 기각.
- **`claude/settings.json`을 계정별로 분리**: 두 계정이 같은 원본을 공유하는 현재 구조
  (`docs/decisions/2026-07-multi-account-claude-config.md`)를 깨뜨린다. 기각.
- **환경변수만 제공**: 위의 전달 보장 문제로 단독 채택하지 않고, 파일과 병행.
- **볼륨 0으로 설정**: Linux 터미널 벨(`\a`)에는 볼륨 개념이 없다. 기각.

## 결과

- 소리를 끄고 켜는 것이 리포 변경 없이 파일 하나로 끝난다
- Claude·Codex 훅이 같은 스위치를 본다(Agent Parity)
- 새 사운드 훅을 추가할 때 `play_sound()`를 우회하면 `check.sh`가 잡는다
