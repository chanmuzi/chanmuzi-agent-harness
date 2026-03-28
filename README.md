# chanmuzi-agent-harness

Claude Code와 Codex CLI 설정을 여러 머신에서 동기화하기 위한 통합 harness.

## 포함된 파일

| 경로 | 용도 |
|------|------|
| `shared/lib/os.sh` | 크로스플랫폼 헬퍼 (sed, readlink, sound) |
| `shared/shell/init.sh` | 쉘 함수 (`claude`, `codex`, `codex-safe` 등) |
| `shared/hooks/` | 공용 hooks (block-no-verify, play-sound) |
| `claude/CLAUDE.md` | Claude Code 글로벌 지시사항 |
| `claude/settings.json` | 권한, hooks, 플러그인 설정 |
| `claude/statusline.sh` | 커스텀 상태바 |
| `claude/hooks/` | Claude 전용 hooks |
| `claude/commands/` | 커스텀 slash commands |
| `codex/AGENTS.md` | Codex 글로벌 지시사항 |
| `codex/profile.toml` | 관리형 프로필 (`[profiles.harness]`) |
| `codex/hooks.json` | Codex hook 설정 |
| `codex/hooks/` | Codex 전용 hooks |
| `codex/skills.txt` | 자동 설치할 Codex skills 목록 |
| `codex/external-skills.json` | 외부 skill repo 설치 목록 |
| `templates/AGENTS.md` | 프로젝트별 AGENTS.md 템플릿 |

`context7`는 curated skill로 설치하지 않고 `~/.agents/skills/context7`를
`~/.codex/skills/context7`에 심링크하는 방식으로 관리합니다.
새 머신에서는 이 디렉터리가 비어 있을 수 있으므로, `setup.sh`에서
`context7 not found in ~/.agents/skills/context7` 경고가 나올 수 있습니다.
이 경고는 `context7`만 빠졌다는 뜻이며 다른 설정은 계속 진행됩니다.

## 새 머신에 세팅하기

### 1. 사전 요구사항

```bash
# Node.js (>= 18)
node --version

# Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Codex CLI
npm install -g @openai/codex

# jq (hooks에서 사용)
brew install jq        # macOS
sudo apt install jq    # Ubuntu/Debian
```

### 2. 설치

```bash
git clone git@github.com:chanmuzi/chanmuzi-agent-harness.git ~/chanmuzi-agent-harness
cd ~/chanmuzi-agent-harness
chmod +x setup.sh check.sh
./setup.sh
```

> **클론 경로는 자유입니다.** `setup.sh`가 실행 시 현재 repo 경로를 자동 감지하여
> `CHANMUZI_AGENT_HARNESS_HOME` 환경변수를 쉘 RC에 등록합니다.
> Claude/Codex hooks는 이 환경변수를 통해 `shared/lib/os.sh` 등 공용 헬퍼를 찾으므로,
> 설치 후 **쉘을 재시작**하거나 `source ~/.zshrc` (또는 `~/.bashrc`)를 실행하세요.

### 3. 선택적 설치

```bash
./setup.sh --claude    # Claude Code만
./setup.sh --codex     # Codex CLI만
./setup.sh             # 둘 다 (기본)
```

### 3-1. context7 복구

`context7`를 실제로 사용한다면 새 머신에서 별도로 채워줘야 합니다.
이 harness는 `~/.agents/skills/context7`를 `~/.codex/skills/context7`에
심링크만 하며, 원본 스킬 자체를 자동 다운로드하지는 않습니다.

가장 간단한 방법은 기존에 잘 쓰고 있는 다른 머신에서 `SKILL.md`를 복사하는 것입니다.

```bash
mkdir -p ~/.agents/skills/context7
```

다른 머신에서 현재 머신으로 복사:

```bash
scp ~/.agents/skills/context7/SKILL.md \
  <user>@<host>:~/.agents/skills/context7/SKILL.md
```

복사 후 다시 실행:

```bash
./setup.sh --codex
./check.sh
```

확인 포인트:

- `~/.agents/skills/context7/SKILL.md`가 존재해야 합니다.
- `~/.codex/skills/context7`는 `setup.sh`가 만든 심링크여야 합니다.
- `setup.sh`에서 `context7` 경고가 사라져야 합니다.

### 4. 검증

```bash
./check.sh
```

## 쉘 명령어

### Claude Code

| 명령어 | 설명 |
|--------|------|
| `claude` | 권한 스킵 (hooks가 안전장치) |
| `claude-safe` | 기본 권한 모드 |
| `claude-team [name]` | tmux 세션에서 실행 |
| `claude-team-safe [name]` | tmux + 기본 권한 |

### Codex CLI

| 명령어 | 설명 |
|--------|------|
| `codex` | 승인/샌드박스 바이패스 (hooks가 안전장치) |
| `codex-safe` | 승인 있음 + 샌드박스 (`-a on-request -s workspace-write`) |

`./setup.sh --codex`는 현재 harness 저장소 경로를 `~/.codex/config.toml`의
`[projects."<repo path>"]`에 `trust_level = "trusted"`로 등록합니다.
이 trust 설정은 approval/sandbox 옵션과 별개입니다.

## 업데이트

```bash
cd ~/chanmuzi-agent-harness
git pull
./setup.sh
```

## 설정 관리 방식

| 도구 | 방식 | 이유 |
|------|------|------|
| Claude Code | 심링크 (전체 교체) | `settings.json`이 100% 공통 설정 |
| Codex CLI | 심링크 + config.toml patch | `config.toml`에 머신별 설정(projects, MCP)이 섞여 있음 |

Codex의 `config.toml`에서 harness가 관리하는 영역은 `[profiles.harness]` 블록과
현재 harness 저장소의 `projects."<repo path>".trust_level` 엔트리뿐이며,
다른 `projects.*`, `mcp_servers.*`, `plugins.*`는 건드리지 않습니다.
