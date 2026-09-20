# git-claw 공통 규칙과 작성 도구 표기 분리

## 상태

채택 (2026-09)

## 맥락

Codex에서 issue 스킬을 사용했는데도 공통 훅이 Claude Code 생성 문구만
인정해 등록을 차단했다. Codex에 설치하는 git-claw 원본 템플릿에도 같은
문구가 고정돼 있었다. 명령 문자열 전체에서 문구를 찾으므로 `--body-file`의
정상 본문은 읽지 못하고, 반대로 제목이나 다른 명령에 있는 문구를 인정했다.

`ENFORCE_GIT_CLAW=0`을 등록 명령 앞에 붙이라는 안내도 실행 전 훅의
동작과 달랐다. 그 변수는 아직 실행되지 않은 명령의 환경이므로 훅에
전달되지 않는다. FileSearch 두 건에 대한 임시 예외는 영구 비활성화나
다른 작업의 예외 승인으로 확대하지 않는다.

## 결정

- staging, commit 제목, PR 제목과 draft 제한은 공통 훅에 유지한다.
- Claude/Codex 래퍼가 도구 식별자를 공통 훅에 전달한다. issue 본문의
  `Generated with [Claude Code]` / `Generated with [Codex]` 행을 구분한다.
  마커는 양식 검사이며 스킬 실행 여부를 인증하는 수단은 아니다.
- Codex 설치 사본의 git-claw Markdown에서 생성 문구만 Codex로 정규화한다.
  Claude 플러그인 원본과 양쪽 템플릿 구조는 유지한다. upstream 저장소 전체를
  fork하거나 실제 작성 도구를 거짓 표기하지 않는다. 기존 ref가 같아 설치를
  생략하는 경로와 새 설치 모두에 정규화를 적용한다.
- issue 본문은 셸을 실행하지 않고 읽는다. literal `--body`/`-b`, 스킬의
  cat heredoc, 기존 일반 파일의 `--body-file`/`-F`를 지원한다. 공백·한글 경로,
  `=` 형식, 훅 payload의 cwd와 단순 `cd path &&`를 처리한다.
- 동적 경로·본문, stdin, 아직 생성하지 않은 파일은 승인으로 추정하지 않고
  기존 파일의 절대 경로로 다시 시도하도록 안내한다. 본문 파일은 별도 도구
  호출에서 먼저 작성한다. FIFO 등 일반 파일이 아닌 입력은 읽지 않는다.
- 예외 변수는 **훅 프로세스 환경**에서만 읽는 기존 의미를 유지한다. 명령
  접두어로 범용 우회 기능을 새로 만들지 않는다. 사용자가 명시적으로 승인한
  작업에 한해 훅 환경에 임시 적용하고 즉시 복구해야 하며, 상시 설정 변경은
  승인된 것이 아니다. 정상 등록 실패는 본문과 템플릿을 바로잡아 해결한다.

## 결과와 한계

설치된 issue와 코드 리뷰 템플릿의 생성 문구를 `check.sh`에서 검증한다.
실제 래퍼를 호출하는 회귀 검증은 다음과 같다.

```sh
bash shared/hooks/enforce-git-claw.test.sh
python3 -B shared/hooks/issue-body.test.py
./setup.sh
./check.sh
```

이 훅은 범용 셸 보안 경계나 셸 인터프리터가 아니다. 지원하지 않는 동적
입력은 평가하지 않는다. 네트워크 오류로 external skill discovery 자체가
실패하면 setup의 기존 설치 생략 정책이 적용되며, check가 설치본 표기 누락을
찾으면 네트워크 복구 후 setup을 다시 실행한다.

FileSearch 실험·제품 저장소, 기존 이슈 두 건, 외부 git-claw 저장소의 배포는
변경하지 않는다.
