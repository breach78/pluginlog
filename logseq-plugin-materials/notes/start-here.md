# Start Here

## 추천 순서

1. `../repos/official/logseq-docs/pages/Plugins 101.md`
   - 공식 문서 쪽에서 플러그인 개발 자료를 어디로 연결하는지 먼저 본다.
2. `../repos/official/logseq-docs/pages/Plugins 01.md`
   - 가장 작은 Hello World 흐름을 확인한다.
3. `../repos/official/logseq-plugin-samples/README.md`
   - 어떤 샘플이 있는지 보고 가장 비슷한 예제를 고른다.
4. `../repos/official/logseq-plugins-docs/README.md`
   - API 문서 루트와 SDK 문서 링크를 확인한다.
5. `../repos/official/logseq-marketplace/README.md`
   - 배포와 제출 규칙을 확인한다.

## 어떤 저장소에서 시작할지

### 1) 가장 단순한 플러그인

- 추천: `../repos/official/logseq-plugin-samples/logseq-hello-world`
- 이유: 구조가 작고 Logseq 플러그인의 최소 형태를 바로 볼 수 있다.

### 2) 일반적인 TypeScript 플러그인

- 추천: `../repos/community/logseq-plugin-sample-kit-typescript`
- 이유: React 없이 가볍고, l10n과 file graph/DB graph 체크가 포함되어 있다.

### 3) UI가 큰 플러그인

- 추천: `../repos/community/logseq-plugin-template-react`
- 이유: React + Vite + HMR 기반이라 패널 UI나 설정 화면이 큰 플러그인에 유리하다.

### 4) ClojureScript 기반 플러그인

- 추천: `../repos/official/cljs-plugin-example`
- 이유: Logseq 공식 SDK 문서에서 따로 가리키는 예제이고, `bb run dev` / `bb run build` 흐름이 단순하다.

## 구현 전에 기억할 점

- 공식 샘플과 마켓플레이스 문서 모두 `@logseq/libs`를 최신으로 유지하라고 안내한다.
- 공식 튜토리얼 기준 최소 `package.json`에는 `name`, `main`, `logseq`가 필요하다.
- 마켓플레이스 제출 전에는 릴리스 zip, README 설명, 이미지/gif가 필요하다.
- DB graph 지원 여부는 나중에 `supportsDB`, `supportsDBOnly` 같은 필드로 명시할 수 있다.

## 다음 실무 순서

1. 원하는 템플릿 하나를 복사해 새 플러그인 저장소를 만든다.
2. Logseq 데스크톱에서 Developer Mode를 켠다.
3. `Load unpacked plugin`으로 템플릿 폴더를 로드한다.
4. 동작이 잡히면 마켓플레이스 제출 형태로 정리한다.
