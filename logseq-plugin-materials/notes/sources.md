# Sources

수집 기준일: 2026-04-23

## 공식 자료

### `logseq/cljs-plugin-example`

- 로컬 경로: `../repos/official/cljs-plugin-example`
- 현재 커밋: `5ea3f32`
- 선택 이유:
  - `@logseq/libs` API 문서가 별도 community template로 가리키는 예제다.
  - ClojureScript로 플러그인을 시작할 때 가장 직접적인 출발점이다.
- 원본:
  - https://github.com/logseq/cljs-plugin-example

### `logseq/logseq-plugin-samples`

- 로컬 경로: `../repos/official/logseq-plugin-samples`
- 현재 커밋: `2ea03c4`
- 선택 이유:
  - Logseq 공식 샘플 모음이다.
  - `hello-world`, slash command, calendar, pomodoro, translator 같은 출발점이 이미 있다.
  - 공식 README에서 플러그인 API 문서와 데스크톱 앱 개발자 모드 로드 절차를 직접 안내한다.
- 원본:
  - https://github.com/logseq/logseq-plugin-samples

### `logseq/plugins`

- 로컬 경로: `../repos/official/logseq-plugins-docs`
- 현재 커밋: `3e868c5`
- 선택 이유:
  - `plugins-doc.logseq.com`와 `logseq.github.io/plugins`의 소스 저장소다.
  - API 이름과 문서 구조를 로컬에서 따라가기 좋다.
- 원본:
  - https://github.com/logseq/plugins
  - https://plugins-doc.logseq.com/
  - https://logseq.github.io/plugins/

### `logseq/docs`

- 로컬 경로: `../repos/official/logseq-docs`
- 현재 커밋: `c625d73`
- 선택 이유:
  - `Plugins 101.md`, `Plugins 01.md`, `Plugins 02 - Build a mind map plugin.md` 같은 공식 튜토리얼이 있다.
  - 플러그인 개발 흐름을 문서 관점에서 빠르게 파악할 수 있다.
- 원본:
  - https://github.com/logseq/docs

### `logseq/marketplace`

- 로컬 경로: `../repos/official/logseq-marketplace`
- 현재 커밋: `2c9e7f8`
- 선택 이유:
  - 제출용 `manifest.json` 필드와 배포 조건을 공식 README에서 설명한다.
  - `packages/*/manifest.json` 실전 예시가 많아서 제출 형태를 맞추기 쉽다.
- 원본:
  - https://github.com/logseq/marketplace

## 커뮤니티 템플릿

### `YU000jp/logseq-plugin-sample-kit-typescript`

- 로컬 경로: `../repos/community/logseq-plugin-sample-kit-typescript`
- 현재 커밋: `5be70f6`
- 선택 이유:
  - React 없이 시작하는 TypeScript 템플릿이다.
  - l10n과 file graph/DB graph 체크가 이미 들어 있어 실전 출발점으로 좋다.
- 원본:
  - https://github.com/YU000jp/logseq-plugin-sample-kit-typescript

### `pengx17/logseq-plugin-template-react`

- 로컬 경로: `../repos/community/logseq-plugin-template-react`
- 현재 커밋: `7a6a718`
- 선택 이유:
  - React 기반 UI 플러그인을 빠르게 시작할 수 있다.
  - Vite, HMR, pnpm 구성이 잡혀 있다.
- 원본:
  - https://github.com/pengx17/logseq-plugin-template-react

## 참고만 남긴 공식 링크

### `logseq/logseq`

- 이번에는 클론하지 않았다.
- 이유:
  - 코어 앱 저장소라 초기 플러그인 개발 범위를 넘기 쉽다.
  - 현재 단계에서는 샘플, API 문서, 마켓플레이스 자료만으로 시작 가능하다.
- 원본:
  - https://github.com/logseq/logseq
