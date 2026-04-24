# 120: 아웃라이너 프로토타입 텍스트 → 노드 기반 전환 계획

작성일: 2026-03-31
상태: Draft
범위: `OutlinerView`를 NSTextView 기반 싱글-텍스트 에디터에서 Logseq 스타일 노드-트리 기반 불렛 아웃라이너로 전환한다.

---

## 배경

현재 `OutlinerView`는 NSTextView 하나로 전체 문서를 편집하는 구조다.
불렛(`•`), 체크박스(`☐`), 들여쓰기 가이드 라인이 모두 텍스트 문자로 표현된다.
이 때문에 백스페이스로 불렛이 지워지고, 불렛 클릭으로 줌인할 수 없으며,
체크박스와 텍스트의 경계가 없다.

목표: Logseq/WorkFlowy처럼 **불렛/체크박스가 텍스트 영역과 완전히 분리**된 아웃라이너로 바꾼다.

---

## 관련 문서

- `119_EXPERIMENTAL_DETAIL_OUTLINER_MVP_PLAN.md` — 실험용 아웃라이너 MVP 계획 (이 문서의 전제)
- `120_OUTLINER_SYNC_AND_MIGRATION_PHASE_PLAN.md` — 기존 앱 sync identity 이관 및 첫 sync 안전 정책

이 문서는 위 두 문서와 **함께** 읽어야 한다.
특히 `120_OUTLINER_SYNC_AND_MIGRATION_PHASE_PLAN.md`의 identity 이관 정책과 first sync gate가 이 전환 계획의 데이터 모델과 sidecar 설계에 직접 영향을 준다.

---

## 변환 원칙

1. **기존 Reminders sync 로직은 건드리지 않는다.** `OutlinerLiveSync.swift`의 인터페이스를 그대로 유지한다.
2. **기존 엔진의 알고리즘은 포팅한다.** 재정렬, 부모 변경, 삭제, 접기 로직은 텍스트 대신 노드 배열을 받도록 바꾸되, 핵심 규칙은 동일하게 유지한다.
3. **Sidecar 저장 형식은 호환을 유지한다.** JSON 구조가 바뀌면 기존 저장 데이터가 유실될 수 있으므로, 가능하면 migration 경로를 둔다.
4. **인스펙터(오른쪽 패널)는 그대로 둔다.** 데이터 소스만 바뀌고 UI는 유지한다.
5. **정식 편입에 필요한 identity 필드를 처음부터 예약한다.** 지금은 사용하지 않더라도 `migratedTaskItemID`, `reminderExternalIdentifier` 필드를 sidecar 데이터 모델(노드)에 넣어둬서 나중에 migration을 한 번 더 하지 않도록 한다.
6. **first sync gate를 준수한다.** `120_OUTLINER_SYNC_AND_MIGRATION_PHASE_PLAN.md` Phase 0의 정책에 따라, `firstSyncCompleted` 플래그가 `false`일 때 bulk push를 차단하는 분기를 이 전환에서 함께 넣는다.

---

## 현재 파일 구조와 역할

| 파일 | 줄 수 | 역할 | 전환 후 |
|---|---|---|---|
| `OutlinerView.swift` | 1,893 | 메인 뷰 + NSTextView wrapper + 인스펙터 + 에디터 엔진 | **전면 재작성** |
| `OutlinerModels.swift` | 1,467 | 데이터 모델 + 파서 + 엔진들 (reorder, reparent, delete, collapse, tree nav, sync contract, anchor codec) | **부분 재작성** |
| `OutlinerLiveSync.swift` | 589 | Reminders sync controller | **최소 수정** (노드 ID 기반 어댑터로 변경) |
| `OutlinerSidecarStore.swift` | 60 | JSON 영속 저장 | **수정** (새 노드 모델 직렬화 및 identity/sync 플래그 추가) |
| `OutlinerLineIndexMapper.swift` | 58 | 텍스트 변경 시 줄 인덱스 재매핑 | **삭제** (노드 ID 기반이므로 불필요) |
| `OutlinerWindowController.swift` | 48 | 창 관리 | **변경 없음** |

---

## 새 데이터 모델

### OutlineNode

```swift
/// 하나의 아웃라이너 노드.
/// 텍스트와 불렛/체크박스 타입이 분리되어 있다.
struct OutlineNode: Identifiable, Equatable {
    let id: UUID
    var text: String              // 순수 텍스트만. 마커 문자 없음.
    var type: OutlineNodeType     // .bullet / .task(completed: Bool)
    var children: [OutlineNode]
    var isCollapsed: Bool

    // --- 정식 편입 대비 identity 예약 필드 ---
    var migratedTaskItemID: String?            // 기존 앱 TaskItem.id (migration 시 채움)
    var reminderIdentifier: String?            // EKReminder.calendarItemIdentifier
    var reminderExternalIdentifier: String?    // EKReminder.calendarItemExternalIdentifier
}

enum OutlineNodeType: Equatable {
    case bullet
    case task(completed: Bool)
}
