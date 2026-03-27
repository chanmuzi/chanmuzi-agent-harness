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
| `templates/AGENTS.md` | 프로젝트별 AGENTS.md 템플릿 |

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

### 3. 선택적 설치

```bash
./setup.sh --claude    # Claude Code만
./setup.sh --codex     # Codex CLI만
./setup.sh             # 둘 다 (기본)
```

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
| `codex` | 승인 없이 + 샌드박스 (`-a never -s workspace-write`) |
| `codex-safe` | 승인 있음 + 샌드박스 (`-a on-request -s workspace-write`) |
| `codex-y` | 완전 무제한 (`--dangerously-bypass-approvals-and-sandbox`) |

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

Codex의 `config.toml`에서 harness가 관리하는 영역은 `[profiles.harness]` 블록뿐이며,
`projects.*`, `mcp_servers.*`, `plugins.*`는 절대 건드리지 않습니다.
