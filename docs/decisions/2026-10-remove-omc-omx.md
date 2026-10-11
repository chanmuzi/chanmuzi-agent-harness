# 2026-10 — oh-my-claudecode / oh-my-codex를 harness에서 제거한다

## 상태

채택 (2026-10-11)

## 맥락

이 harness는 Claude Code 플러그인 `oh-my-claudecode@omc`(OMC)를 두 계정 모두에 활성화하고,
`setup.sh`가 OMC 스킬(`deep-interview`)을 패치했으며, Codex 쪽에는 `oh-my-codex`(OMX) CLI
설치 옵션(`--install-omx`)과 "project scope로만 쓴다"는 정책·검사가 있었다.

제거를 결정하기 전에 실사용 흔적을 세션 트랜스크립트(`~/.claude*/projects/**/*.jsonl`)에서
전수 조사했다:

| 항목 | cc (`~/.claude`) | ccu (`~/.claude-upstage`) |
|---|---|---|
| 최근 90일 세션 수 | 191 | 162 |
| OMC 스킬·에이전트 호출 (`Skill`/`Agent`) | 0 | 0 |
| OMC 슬래시 명령 직접 입력 | 0 | 0 |
| OMC MCP 도구 호출 (전체 기간) | 4회 (마지막 2026-09-07) | 3회 (wiki 조회) |
| `omx` CLI 설치 여부 | 미설치 | 미설치 |

반면 비용은 매 세션 고정으로 들어갔다. OMC 5.6.0은 11개 이벤트에 훅 14개를 걸고,
스킬 48개·에이전트 19개·MCP 도구 70여 개를 매 세션 등록한다. 스킬 description이
컨텍스트 1%를 넘쳐 `skillListingBudgetFraction`을 올린 커밋(a094329)도 OMC가 원인이었고,
세션 시작마다 "[OMC] HUD not configured" 경고가 주입됐다.

외부 오케스트레이션 레이어를 얹기보다 모델과 Claude Code 기본 harness가 제공하는
계획·검증·서브에이전트 기능을 그대로 쓰는 편이 지시 충돌과 컨텍스트 낭비가 적다는 판단도
있었지만, 결정의 1차 근거는 위의 "쓰지 않는다"는 데이터다.

## 결정

- `claude/settings.json`에서 OMC 관련 항목을 모두 제거한다:
  `enabledPlugins["oh-my-claudecode@omc"]`, `extraKnownMarketplaces.omc`,
  `env.OMC_SKIP_HOOKS`, 최하단 `omc.deepDive`. OMC 때문에 올렸던
  `skillListingBudgetFraction`도 기본값으로 되돌린다(키 삭제).
- `setup.sh`에서 OMC 플러그인 패치 블록, `--install-omx` 옵션과 설치 섹션, omx 안내 메시지,
  `.omc/`/`.omx/` global gitignore 등록을 제거한다.
- `check.sh`에서 omx CLI 존재 검사와 `~/.codex/config.toml`의 OMX user-scope 검사를 제거한다.
- `README.md`에서 "oh-my-codex 정책"과 "OMC 플러그인 패치" 섹션, `--install-omx` 안내를 제거한다.
- 레포 `.gitignore`의 `.omc/`를 제거한다.
- 머신 로컬 플러그인 캐시는 `rm`이 아니라 `claude plugin uninstall oh-my-claudecode@omc`로
  정리한다. Claude Code는 이전 버전 디렉토리에 `.orphaned_at` 마커를 찍고 14일 뒤에 치우므로,
  이미 OMC를 로드한 채 열려 있는 세션은 끝날 때까지 정상 동작한다
  (plugin loading reference, "Cleanup of previous versions").

## 대안

- **OMC는 유지하고 OMX만 제거**: OMC 쪽 사용량도 사실상 0이고, 매 세션 비용은 OMC가
  대부분이라 반쪽 정리가 된다. 기각.
- **플러그인은 비활성화만 하고 설정은 남김**: `enabledPlugins`에 `false`로 두면 설정 파일에
  죽은 marketplace 엔트리와 패치 로직이 남아 다음 사람이 다시 조사하게 된다. 기각.
- **OMC 훅만 `OMC_SKIP_HOOKS`로 더 많이 끄기**: 스킬·에이전트·MCP 도구 등록 비용은 그대로다. 기각.

## 결과

- 매 세션 컨텍스트에서 OMC 스킬·에이전트 description과 MCP 도구 목록, 훅 실행이 사라진다.
- `./setup.sh --install-omx`는 더 이상 유효한 옵션이 아니다. OMX가 다시 필요하면 이 기록을
  읽고 새 결정 기록과 함께 되살린다.
- 과거 결정 기록(`2026-08-plugin-cache-path-normalization.md`, `2026-10-npm-user-prefix.md`)의
  OMC/OMX 언급은 당시 맥락이므로 그대로 둔다.
- 열려 있던 세션은 `claude --resume`으로 다시 열면 OMC 없이 뜬다. 플러그인은 세션 시작 시에만
  로드되므로 실행 중인 세션은 영향을 받지 않는다.
