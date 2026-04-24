# Logseq Plugin Materials

Logseq 플러그인 개발에 바로 필요한 공식 저장소, 대표 템플릿, 참고 문서를 이 폴더에 모아둔 인덱스다.

## 구조

- `repos/official/`
  - `cljs-plugin-example`: 공식 ClojureScript 예제
  - `logseq-plugin-samples`: 공식 샘플 모음
  - `logseq-plugins-docs`: 플러그인 API 문서 사이트 소스
  - `logseq-docs`: 공식 문서 저장소
  - `logseq-marketplace`: 마켓플레이스 제출 규칙과 패키지 manifest 예시
- `repos/community/`
  - `logseq-plugin-sample-kit-typescript`: 가벼운 TypeScript 시작 템플릿
  - `logseq-plugin-template-react`: React/Vite 기반 시작 템플릿
- `notes/`
  - `start-here.md`: 무엇부터 읽을지
  - `sources.md`: 수집한 자료와 선택 이유

## 빠른 시작

1. `notes/start-here.md`를 읽는다.
2. 가장 단순한 시작점은 `repos/official/logseq-plugin-samples/logseq-hello-world`다.
3. React UI가 필요 없으면 `repos/community/logseq-plugin-sample-kit-typescript`를 본다.
4. React UI가 필요하면 `repos/community/logseq-plugin-template-react`에서 시작한다.
5. ClojureScript로 가려면 `repos/official/cljs-plugin-example`을 본다.
6. 배포 직전에는 `repos/official/logseq-marketplace/README.md`를 본다.

## 제외한 것

- `logseq/logseq` 코어 앱 저장소는 초기 플러그인 개발에 비해 무겁고 범위가 커서 이번에는 클론하지 않았다.
- 대신 관련 공식 링크와 진입점은 `notes/sources.md`에 남겼다.
