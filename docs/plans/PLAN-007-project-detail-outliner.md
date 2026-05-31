# PLAN-007 Project Detail Outliner

## Summary

- 프로젝트 디테일 페인을 Logseq/Roam 계열의 가벼운 불릿 아웃라이너로 바꾼다.
- 기존 큰 프로젝트 노트 카드와 분리된 할일 리스트 중심 UI를 제거하고, 프로젝트 노트 본문을 블록 트리로 표시한다.
- `LATER` 같은 상태 라벨 기능은 v1에서 구현하지 않는다.
- 저장 원본은 현재처럼 각 Reminder 목록 안의 숨은 `!프로젝트 노트` 할일의 note를 사용한다.
- 체크박스 블록의 제목/완료/날짜/시간/반복은 Reminder 할일이 원본이고, `!프로젝트 노트`에는 위치/계층/연결 ID만 저장한다.
- 구현 전에 EventKit 반복 할일 완료 동작과 macOS 네이티브 아웃라이너 입력 처리를 spike로 검증한다.

## Visual and UX

- 블록은 연한 회색 bullet dot, 들여쓰기, 세로 guide line 형태로 렌더링한다.
- 들여쓰기된 자식 블록은 부모 bullet 아래 세로선으로 연결되어 보이게 한다.
- 체크박스 블록은 `LATER` 없이 `□ 할일 제목` 형태로만 보인다.
- 체크박스 블록 오른쪽에는 날짜, 시간, 반복 칩을 표시한다.
- 날짜/시간/반복 칩을 클릭하면 기존 할일 상세 옵션과 같은 팝업을 열어 수정하거나 삭제할 수 있게 한다.
- 일반 블록과 체크박스 블록 모두 같은 아웃라이너 안에서 편집된다.
- 클릭하면 해당 블록을 inline 편집한다.
- `Enter`는 새 sibling block을 만든다.
- `Shift+Enter`는 현재 블록 내부 줄바꿈을 만든다.
- `Tab`/`Shift+Tab`은 indent/outdent로 동작한다.
- 반복 할일을 완료하면 즉시 체크된 상태로 흐리게 보이고, 약 2초 뒤 반복 아이콘 왼쪽 count를 올린 뒤 다음 반복 회차의 unchecked 블록으로 되돌린다.
- 연결된 Reminder가 아직 로드되지 않은 체크박스 블록은 제목 영역에 `불러오는 중...` placeholder를 표시하고 편집/완료/칩 조작은 비활성화한다.
- 기존 Reminder 할일 목록은 아래 접힘 섹션으로 남긴다.

## Outliner Interaction Engine

- 아웃라이너의 최소 단위는 line이 아니라 block이다. block은 Shift+Enter로 삽입된 soft newline을 내부에 포함할 수 있다.
- 문서 내부 자료구조는 flat array + `depth`를 기본으로 한다. 렌더링 시에만 트리로 해석하고, 이동/indent/outdent/delete는 flat subtree range 연산으로 처리한다.
- 각 블록은 `blockID`, `depth`, `text`, `taskBinding?`, `childrenCollapsed`, `editingState`, `selectionState`를 가진다.
- 체크박스 task block도 구조적으로 일반 block과 동일하다. 단, 표시 text는 Reminder에서 읽고, 저장 text는 비워 둔다.
- 편집 모드는 editing, selected, multi-selected 세 가지다. 한 번에 editing block은 하나뿐이고 selected mode는 다중 선택을 허용한다.
- 커서는 항상 block content 영역 안에만 존재한다. bullet dot/indent guide 위치로 caret이 빠지는 상태는 금지한다.
- text 영역 click은 editing mode, bullet dot click은 selected mode로 전환한다. 자식이 있는 block의 bullet affordance는 fold/unfold도 처리한다.
- `visible block`은 자기 자신과 모든 ancestor가 접힘 상태가 아닌 block이다. 접힌 parent block 자체는 visible이고, 그 descendant는 visible하지 않다.
- keyboard navigation, visible range selection, drag hover target은 visible block만 대상으로 삼는다. 단, visible parent가 선택/이동/삭제되면 hidden descendant도 같은 subtree로 함께 처리한다.
- multi-selected range에서 구조 변경을 할 때는 선택된 visible block 중 다른 선택 block의 descendant인 항목을 제외하고 top-level selected roots만 순서대로 처리한다.

### Keyboard Rules

- `Enter`: caret이 중간이면 block split, 뒤 텍스트는 같은 depth의 새 sibling으로 이동하고 caret은 새 block 앞에 둔다.
- `Enter`: caret이 끝이고 자식이 없으면 같은 depth의 새 sibling을 바로 아래에 만든다.
- `Enter`: caret이 끝이고 자식이 있으며 block이 펼쳐져 있으면 children level의 첫 자식으로 새 block을 만든다.
- `Enter`: caret이 맨 앞이면 현재 block 앞에 같은 depth의 빈 sibling을 만들고 caret은 기존 block에 남긴다.
- `Enter`: 빈 block에서 depth > 0이면 삭제하지 않고 한 단계 outdent한다. 빈 root block에서는 no-op.
- `Shift+Enter`: 현재 block 내부에 soft newline을 삽입한다.
- `Tab`: 현재 block 또는 selected visible range를 indent한다. 같은 depth의 이전 sibling이 있을 때만 가능하며, 대상 block/subtree는 이전 sibling의 마지막 자식이 된다.
- `Shift+Tab`: 현재 block 또는 selected visible range를 outdent한다. depth 0에서는 no-op이며, outdent된 block/subtree는 현재 parent 바로 아래 sibling이 된다.
- `Backspace`: text 중간에서는 표준 문자 삭제를 따른다.
- `Backspace` at position 0: 이전 visible block이 비어 있으면 이전 빈 block만 삭제하고 현재 block은 유지한다.
- `Backspace` at position 0: 이전 visible block에 내용이 있으면 현재 block text를 이전 block 끝에 merge하고 현재 block을 삭제한다.
- `Backspace` at position 0: 이전 block이 없고 depth > 0이면 outdent한다. 이전 block이 없고 depth 0이면 no-op.
- `Delete` at block end: 다음 visible block이 있으면 다음 block text를 현재 block 끝에 merge하고 다음 block을 삭제한다. 다음 block이 없으면 no-op.
- 체크박스 task block과 일반 block 또는 task block끼리는 text merge하지 않는다. merge 상황에서는 outdent를 먼저 시도하고 불가능하면 no-op.
- `Up`/`Down`: block 내부 중간 줄에서는 표준 텍스트 이동을 따른다. 첫 줄 맨 앞/마지막 줄 맨 끝 경계에서는 이전/다음 visible block의 같은 x 위치로 caret을 이동한다.
- `Left` at position 0은 이전 visible block 끝으로 이동한다. `Right` at block end는 다음 visible block 앞으로 이동한다.
- IME marked text가 있는 동안에는 `Enter`, `Tab`, `Backspace`, `Delete` 같은 구조 변경 handler를 실행하지 않는다. 먼저 NSTextView/IME에 이벤트를 넘겨 조합을 확정하거나 수정하게 하고, 구조 변경은 조합이 끝난 뒤의 다음 key event에서만 수행한다.
- 한국어 조합 중 `Enter`는 block split이 아니라 조합 확정으로 처리한다. 같은 위치에서 다시 `Enter`를 눌렀을 때만 일반 `Enter` 규칙을 적용한다.
- `Shift+Left`/`Shift+Right`: editing mode에서는 macOS 기본 텍스트 선택을 유지한다.
- `Shift+Up`/`Shift+Down`: selected mode 또는 caret 경계에서 visible block range selection을 확장한다.
- `Cmd+A`: editing mode에서 1회는 현재 block text 전체 선택, 연속 2회는 전체 visible blocks selection으로 확장한다.
- `Esc`: editing mode를 끝내고 현재 block selected mode로 전환한다.
- selected mode에서 `Up`/`Down`은 이전/다음 visible block 선택으로 이동하고, `Enter` 또는 일반 문자 입력은 editing mode로 진입한다.
- selected mode에서 `Backspace`/`Delete`는 선택된 visible block range를 삭제한다. 연결 Reminder가 있는 task block은 Data and Sync 삭제 정책을 따른다.
- `Cmd+Enter`: 일반 block을 task block으로 전환하거나 task block 완료 상태를 토글한다.
- `Cmd+Shift+Up`/`Cmd+Shift+Down`: 현재 block/subtree를 이전/다음 sibling 위/아래로 이동한다. sibling이 없으면 no-op.
- `Cmd+Up`/`Cmd+Down`: 자식이 있는 현재 block을 fold/unfold한다.

### Shortcut Reference

이 표에 없는 키는 macOS 표준 텍스트 에디터 동작을 따른다.

| Key | Action | Condition |
|---|---|---|
| `Enter` | 새 sibling 생성 / block split / children level 생성 | caret 위치와 자식 존재 여부에 따름 |
| `Enter` | outdent | 빈 block이고 depth > 0 |
| `Shift+Enter` | block 내부 soft newline | 항상 |
| `Tab` | indent | 같은 depth의 이전 sibling이 있을 때 |
| `Shift+Tab` | outdent | depth > 0 |
| `Backspace` | 이전 block 병합 / 이전 빈 block 삭제 / outdent | caret position 0 |
| `Delete` | 다음 block을 현재 block에 병합 | caret이 block 끝 |
| `Up` | 이전 visible block으로 caret 이동 | 첫 줄 맨 앞 또는 selected mode |
| `Down` | 다음 visible block으로 caret 이동 | 마지막 줄 맨 끝 또는 selected mode |
| `Left` | 이전 visible block 끝으로 이동 | caret position 0 |
| `Right` | 다음 visible block 앞으로 이동 | caret이 block 끝 |
| `Cmd+Shift+Up` | block/subtree를 이전 sibling 위로 이동 | 이전 sibling이 있을 때 |
| `Cmd+Shift+Down` | block/subtree를 다음 sibling 아래로 이동 | 다음 sibling이 있을 때 |
| `Cmd+Up` | 현재 block fold | 자식이 있을 때 |
| `Cmd+Down` | 현재 block unfold | 접혀 있을 때 |
| `Esc` | editing mode에서 selected mode로 전환 | 편집 중 |
| `Enter` in selected mode | selected block 편집 진입 | selected mode |
| 일반 문자 in selected mode | selected block 편집 진입 후 입력 | selected mode |
| `Cmd+A` 1회 | 현재 block text 전체 선택 | editing mode |
| `Cmd+A` 연속 2회 | 전체 visible blocks 선택 | editing mode |
| `Backspace`/`Delete` in selected mode | 선택된 block range 삭제 | selected mode |

### Drag, Fold, and Selection

- 드래그는 bullet dot 또는 hover 시 나타나는 drag handle에서만 시작한다. text 영역 drag는 텍스트 선택으로 유지한다.
- bullet drag는 현재 block과 모든 visible/hidden descendant를 하나의 subtree로 이동한다.
- 다중 선택 상태에서 drag하면 selected visible range 전체를 이동한다. v1에서는 visible order 기준 연속 range만 지원한다.
- drop target은 before / after / as child 세 가지를 지원한다. 수평 위치로 child drop을 판정하고, 과도한 depth jump는 직전 sibling depth + 1로 clamp한다.
- 자기 subtree 안으로 drop하는 동작은 금지한다.
- drag 중 원본 block/subtree는 ghosted 상태로 보이고, 삽입 위치는 파란 수평 insertion line으로 표시한다.
- collapsed block 위에 2초 이상 hover하면 자동 unfold한다.
- fold/unfold 상태는 project별 세션 상태로 유지한다. 다른 프로젝트로 갔다 돌아와도 유지한다.
- 접힌 block 끝에서 `Enter`를 누르면 children level이 아니라 접힌 subtree 다음 sibling으로 새 block을 만든다.
- Undo/redo는 outline-only 편집에만 적용한다. 하나의 key action/drag/drop/delete를 하나의 undo group으로 묶는다.
- Reminder 생성/삭제/완료/날짜 변경처럼 실제 Reminder를 변경하는 작업은 v1에서 editor undo stack에 넣지 않는다. pending task block은 Reminder 생성이 완료되기 전까지 undo/cancel 가능하지만, 생성 성공 후 `Cmd+Z`가 Reminder를 자동 삭제하지 않는다.
- task block 삭제는 연결 Reminder 삭제를 의미하므로 outline undo로 자동 복구하지 않는다. 삭제 방지는 기존 앱의 Reminder 삭제 정책과 동일한 확인/롤백 UI를 재사용한다.

### Visual Rendering Rules

- 일반 bullet dot은 6pt 원형이며 연한 회색으로 표시한다.
- 자식이 있는 block은 outline circle, 접힌 block은 filled circle로 구분한다. 자식이 없는 block은 작은 filled dot으로 표시한다.
- 체크박스 task block은 bullet dot 대신 checkbox UI를 표시한다.
- indentation unit은 20pt를 기본값으로 한다.
- depth 1부터 부모 bullet 수직 중앙에서 마지막 자식 bullet 수직 중앙까지 연한 guide line을 그린다. 마지막 자식 아래로 선이 내려가지 않는다.
- guide line click은 해당 parent fold/unfold를 토글한다.
- block hover 시 bullet dot 왼쪽에 drag handle을 표시한다.
- 완료된 task block은 제목에 취소선과 secondary/gray 색상을 적용한다.

### Anti-patterns

- caret이 bullet/indent 영역으로 이동하게 두지 않는다.
- position 0 Backspace에서 이전 빈 block 대신 현재 block을 삭제하지 않는다.
- task block과 일반 block 또는 task block끼리 text merge하지 않는다.
- outdent 직후 editor state 갱신 전에 다음 delete/backspace가 잘못된 block에 적용되지 않도록 한다.
- multi-block selection 후 Up/Down에서 페이지 top/bottom으로 점프하지 않는다.
- Enter가 항상 children level에 block을 만들게 하지 않는다.

## Data and Sync

- 새 타입을 추가한다: `ProjectOutlineDocument`, `ProjectOutlineBlock`, `ProjectOutlineTaskBinding`.
- 숨은 `!프로젝트 노트`의 Markdown을 블록 트리로 파싱하고, 저장 시 다시 Markdown으로 직렬화한다.
- 기존 헤딩/문단은 최초 로드시 일반 블록으로 보존한다.
- 체크박스 블록은 사람이 읽기 쉬울 필요가 없으므로 안정성과 파싱 안전성을 우선해 앱 전용 metadata marker로 저장한다.
- 앱 전용 metadata marker는 일반 Markdown/HTML comment와 충돌하지 않는 단독 bullet content로 둔다. v1 기본형은 `- {{buf-task block="<uuid>" task="<uuid>" external="<external-id>"}}`이다.
- metadata marker parser는 forward-compatible하게 만든다. 알 수 없는 attribute는 무시하되 저장 시 원문 attribute를 보존하고, 필수 attribute가 없거나 깨진 marker는 일반 block으로 degrade한다.
- 체크박스 블록 저장 데이터에는 block ID, Reminder task ID/external ID, 계층 위치만 포함하고 제목 사본은 저장하지 않는다.
- 체크박스 블록 생성 시 pending 블록을 UI에 임시 표시하되, 실제 `!프로젝트 노트` 저장은 Reminder 생성 성공 후 생성된 Reminder 식별자를 metadata에 넣어 확정한다.
- Reminder 생성이 실패하면 pending 블록을 제거하고 오류 표시를 남긴다. ID 없는 체크박스 블록은 문서에 저장하지 않는다.
- 체크박스 블록의 제목, 완료 상태, 날짜, 시간, 반복은 Reminder 할일에서 읽어 렌더링한다.
- 아웃라이너에서 체크박스 블록 제목을 수정하면 기존 앱의 할일 제목 수정 정책을 사용해 Reminder 제목을 수정한다.
- Reminder 앱이나 앱의 다른 화면에서 제목/날짜/반복/완료가 바뀌면 다음 refresh 때 아웃라이너가 Reminder 값을 반영한다.
- 동시 수정 충돌 처리는 v1에서 별도로 만들지 않고 기존 할일 수정 정책을 따른다.
- 아웃라이너 저장 직전에는 task binding validation을 실행한다. 연결 Reminder가 없어진 블록은 저장 전에 삭제/자식 재부착 정책을 적용한다.
- 앱 foreground 변경 알림과 앱 활성화 refresh 모두에서 Reminder 삭제를 감지하고, 백그라운드 삭제 후 편집된 orphan 블록도 저장 직전 validation으로 정리한다.
- 앱 활성화 직후 Reminder refresh가 끝나기 전에는 연결 task block을 `refreshing` 상태로 표시하고 구조 변경/제목 편집/완료 토글을 잠근다. refresh 완료 후 삭제된 Reminder가 확인되면 block 삭제/자식 재부착 정책을 먼저 적용한 뒤 편집을 허용한다.
- 사용자가 refresh 완료 전에 이미 편집 중이던 일반 child block 내용은 보존한다. 단, 삭제된 task block 자신의 제목/완료/칩 편집은 Reminder 원본이 없으므로 버리고 삭제 정책을 적용한다.
- 블록 삭제는 연결된 Reminder 할일 삭제를 의미한다.
- Reminder에서 할일이 삭제되거나 하단 목록에서 삭제되면 연결된 아웃라이너 체크박스 블록도 삭제한다.
- 삭제된 체크박스 블록에 자식 불릿이 있으면 같은 depth의 이전 형제 할일 아래로 붙인다. 이전 형제 할일이 없으면 자식들을 한 단계 outdent해서 삭제된 할일 위치로 올린다.
- 체크박스 블록의 하위 불릿/본문은 Reminder 할일 노트로 동기화하지 않고 프로젝트 노트 안에만 남긴다.
- 기존 하단 할일 섹션은 주로 보기와 드래그 소스로 사용한다. 그 섹션에서 완료/삭제가 일어나면 같은 Reminder ID를 통해 아웃라이너에 반영한다.

## Pre-implementation Spikes

- EventKit 반복 할일 spike: 반복 Reminder 완료 후 0초/2초/refresh 뒤 `calendarItemIdentifier`, external ID, dueDate, recurrence, completion 상태가 어떻게 변하는지 기록한다.
- 반복 완료 구현은 spike 결과에 따라 같은 binding 갱신 또는 새 Reminder ID rebind 중 하나로 확정한다.
- 아웃라이너 입력 spike: `NSViewRepresentable` 기반 block text editor에서 Enter, Shift+Enter, Tab, Shift+Tab, Backspace 병합, 위/아래 포커스 이동, Shift+Arrow selection, IME 조합 입력이 안정적으로 동작하는지 확인한다.
- IME spike는 한국어 조합 중 `Enter`, `Tab`, `Backspace`, `Delete`가 구조 변경으로 오인되지 않는지 별도 케이스로 기록한다.
- 아웃라이너 drag spike: bullet-only drag handle, subtree move, before/after/as-child drop, 자기 subtree drop 금지, insertion indicator가 안정적으로 동작하는지 확인한다.
- Logseq/Roam 조사는 UX와 키보드 동작 참고용으로 사용하고, 웹 editor 구현을 직접 이식하지 않는다.

## Test Plan

- Markdown 파서/직렬화 테스트: 중첩 불릿, 기존 문단 변환, 앱 전용 task metadata marker 보존, 제목 사본 미저장, 기존 HTML comment 오인식 방지.
- UI 정책 테스트: Enter split, Shift+Enter newline, Tab indent, Shift+Tab outdent, Backspace merge/delete, Up/Down focus 이동, Shift+Arrow selection, Cmd+A 단계 선택, Esc block select, IME 조합 중 구조 변경 방지.
- Drag 정책 테스트: bullet drag로 subtree 이동, before/after/as-child drop, depth clamp, 자기 subtree drop 금지, multi-block range drag.
- Task UI 테스트: 체크박스 토글, 날짜/시간/반복 칩, task block 삭제, 하단 목록 삭제 역반영.
- 서비스 테스트: `!프로젝트 노트` 저장, 체크박스 생성 시 Reminder 생성, 제목/완료/날짜/시간/반복 반영, 하위 내용 미동기화.
- 실패 테스트: Reminder 생성 실패 시 pending 블록 rollback, 로드 전 placeholder, 연결 Reminder 없음 상태에서 편집/저장 validation.
- 삭제 테스트: 블록 삭제 시 Reminder 삭제, Reminder 삭제 시 블록 삭제, 자식 불릿 이전 형제 재부착, 이전 형제 부재 시 outdent.
- 반복 테스트: EventKit spike 결과 기반으로 반복 할일 완료 후 2초 유예 UI, count 증가 표시, 다음 반복 회차로 복귀 또는 rebind.
- 백그라운드 테스트: 앱 비활성 중 Reminder 삭제 후 재활성 refresh, 삭제된 블록 편집 시도 후 저장 전 orphan 정리.
- Undo 테스트: outline-only 편집은 undo되고, Reminder commit 이후의 task 생성/삭제/완료/날짜 변경은 editor undo로 자동 되돌리지 않는다.
- 회귀 테스트: 기존 프로젝트 노트 저장, 기존 할일 접힘 섹션, 전체 `swift test`.
- 구현 후 앱 빌드, 기존 앱 종료, 수정 앱 재실행까지 검증한다.

### Required Outliner Cases

- T-OL-01: 빈 block(depth 1)에서 Enter를 누르면 depth 0으로 outdent되고 caret은 유지된다.
- T-OL-02: 내용 있는 block 끝에서 Enter, 자식 없음이면 같은 depth sibling을 만든다.
- T-OL-03: 내용 있는 block 끝에서 Enter, 자식 있음이면 children level 첫 자식을 만든다.
- T-OL-04: block 중간에서 Enter를 누르면 split되고 뒤 내용이 새 sibling으로 이동하며 caret은 새 block 앞에 놓인다.
- T-OL-05: Tab에서 이전 sibling이 없으면 no-op.
- T-OL-06: Tab에서 이전 sibling이 있으면 이전 sibling의 마지막 자식이 되고 subtree도 함께 이동한다.
- T-OL-07: Shift+Tab에서 depth 0이면 no-op.
- T-OL-08: Shift+Tab에서 depth 1 이상이면 parent의 다음 sibling이 되고 subtree도 함께 이동한다.
- T-OL-09: position 0 Backspace, 이전 block이 비어 있으면 이전 빈 block만 삭제한다.
- T-OL-10: position 0 Backspace, 이전 block에 내용이 있으면 이전 block에 merge하고 현재 block을 삭제한다.
- T-OL-11: position 0 Backspace, 이전 block 없음, depth > 0이면 outdent한다.
- T-OL-12: position 0 Backspace, 첫 root block이면 no-op.
- T-OL-13: task block position 0 Backspace에서 일반 block 또는 task block과 text merge하지 않고 outdent/no-op 처리한다.
- T-OL-14: block 끝 Delete, 다음 block이 있으면 다음 block 내용을 현재 block에 merge한다.
- T-OL-15: Cmd+Shift+Up, 첫 sibling이면 no-op.
- T-OL-16: Cmd+Shift+Up, 이전 sibling이 있으면 위 sibling과 순서 교체하고 subtree도 함께 이동한다.
- T-OL-17: Up, 첫 줄 맨 앞이면 이전 visible block의 같은 x 위치로 이동하고, 해당 x 위치가 없으면 그 줄 끝으로 이동한다.
- T-OL-18: Up, 첫 visible block이면 no-op.
- T-OL-19: Left, position 0이면 이전 visible block 끝으로 이동한다.
- T-OL-20: 접힌 block 끝에서 Enter를 누르면 자식 레벨이 아니라 다음 sibling을 만든다.
- T-OL-21: Cmd+A 1회는 현재 block text 전체 선택.
- T-OL-22: Cmd+A 2회 연속은 전체 visible blocks 선택.
- T-OL-23: Esc는 block selected mode로 전환하고, Up/Down 이동과 Enter 편집 진입이 동작한다.
- T-OL-24: multi-block selection 후 Tab은 선택된 visible range 전체를 indent한다.
- T-OL-25: Home/Left 연타/마우스 클릭 등 어떤 경로에서도 caret이 bullet 위치로 이동하지 않는다.
- T-OL-26: 접힌 parent는 visible이고 접힌 descendant는 keyboard navigation/selection 대상에서 제외된다.
- T-OL-27: visible parent를 이동/삭제하면 hidden descendant도 subtree로 함께 이동/삭제된다.
- T-OL-28: 한국어 IME 조합 중 Enter는 조합 확정만 수행하고 block split을 실행하지 않는다.
- T-OL-29: 한국어 IME 조합 중 Tab/Backspace/Delete가 indent/delete handler로 오인되지 않는다.
- T-OL-30: Reminder 생성 성공 후 Cmd+Z는 연결 Reminder를 자동 삭제하지 않는다.

## Assumptions

- v1에서는 `LATER`, TODO 상태 순환, slash command, page ref, block ref, zoom 기능은 제외한다.
- 외부 라이브러리 없이 SwiftUI/AppKit 기반 커스텀 경량 아웃라이너로 구현한다.
- 기존 하단 할일 섹션에는 아웃라이너 체크박스로 만든 할일도 중복 표시한다.
- 기본 아웃라이너 모양과 키보드 동작은 구현 전에 Logseq/Roam 계열 오픈소스 구현을 추가 조사해 적용한다.
- `!프로젝트 노트`의 내부 저장 형식은 사람이 읽을 필요가 없으며, 파싱 안정성·식별자 안정성·오류 복구를 우선한다.
- Reminder 로드 전에도 프로젝트 노트의 outline 구조 저장은 허용한다. 다만 체크박스 블록 제목 사본은 프로젝트 노트에 저장하지 않고 placeholder로 렌더링한다.
