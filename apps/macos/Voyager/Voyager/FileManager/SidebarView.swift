import Foundation
import Inject
import SwiftUI

/// 좌측 사이드바 (탭 목록)
struct SidebarView: View {
    var isFloating: Bool = false
    var onHoverChange: ((Bool) -> Void)?

    @EnvironmentObject var tabManager: TabManager
    @ObserveInjection var inject
    @State private var draggingTab: TabViewModel?
    @State private var dragLocation: CGPoint?
    // 중앙 구분선 제거: 행 사이 경계(마지막 핀/첫 언핀)를 사용
    @State private var boundaryY: CGFloat?
    @State private var dropTargetId: UUID?
    @State private var dropTargetAbove: Bool = false

    var body: some View {
        content
            .frame(maxHeight: .infinity)
            .background(isFloating ? Color(red: 0.18, green: 0.18, blue: 0.20) : .clear)
            .cornerRadius(isFloating ? 8 : 0)
            .shadow(color: .black.opacity(isFloating ? 0.5 : 0), radius: isFloating ? 20 : 0, x: isFloating ? 5 : 0)
            .padding(isFloating ? 6 : 0)
            .frame(width: isFloating ? 220 : nil)
            .transition(isFloating ? .move(edge: .leading) : .identity)
            .onHover { hovering in
                if isFloating {
                    onHoverChange?(hovering)
                }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 핀된 탭 섹션
            ForEach(Array(tabManager.pinnedTabs.enumerated()), id: \.element.id) { index, tab in
                TabRowView(
                    tab: tab,
                    draggingTab: $draggingTab,
                    dragLocation: $dragLocation,
                    boundaryY: $boundaryY,
                    dropTargetId: $dropTargetId,
                    dropTargetAbove: $dropTargetAbove
                )
                .background(
                    // 마지막 핀 탭의 하단을 경계로 사용
                    (tabManager.pinnedTabs.last?.id == tab.id) ? GeometryReader { geo in
                        Color.clear.onAppear { boundaryY = geo.frame(in: .global).maxY }
                            .onChange(of: tabManager.pinnedTabs.count) { _ in
                                boundaryY = geo.frame(in: .global).maxY
                            }
                    } : nil
                )
                .environmentObject(tabManager)

                // 탭들 사이의 구분선 영역 (마지막 탭 제외)
                if index < tabManager.pinnedTabs.count - 1 {
                    TabDividerView(
                        tabId: tab.id,
                        draggingTab: $draggingTab,
                        dragLocation: $dragLocation,
                        dropTargetId: $dropTargetId,
                        dropTargetAbove: $dropTargetAbove
                    )
                }
            }

            // 시각적 구분선(핀 영역이 비어있을 때 드롭 인디케이터로 작동)
            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    // 핀 영역이 비어있을 때 언핀 탭을 핀 영역으로 드래그하면 구분선이 드롭 인디케이터로 작동
                    Group {
                        if tabManager.pinnedTabs.isEmpty,
                           let dragging = draggingTab,
                           !dragging.isPinned,
                           let dragLoc = dragLocation
                        {
                            // 구분선 영역 내에 드래그가 있으면 파란색 인디케이터 표시
                            let dividerTop = -8.0
                            let dividerBottom = 8.0

                            if dragLoc.y >= dividerTop && dragLoc.y <= dividerBottom {
                                Color.blue
                                    .frame(height: 2)
                                    .transition(.opacity)
                            }
                        }
                    }
                )

            // 일반 탭 섹션
            ForEach(Array(tabManager.unpinnedTabs.enumerated()), id: \.element.id) { index, tab in
                TabRowView(
                    tab: tab,
                    draggingTab: $draggingTab,
                    dragLocation: $dragLocation,
                    boundaryY: $boundaryY,
                    dropTargetId: $dropTargetId,
                    dropTargetAbove: $dropTargetAbove
                )
                .background(
                    // 핀된 탭이 없을 때 첫 언핀 탭의 상단을 경계로 사용
                    (tabManager.pinnedTabs.isEmpty && tabManager.unpinnedTabs.first?.id == tab.id) ?
                        GeometryReader { geo in
                            Color.clear.onAppear { boundaryY = geo.frame(in: .global).minY }
                                .onChange(of: tabManager.unpinnedTabs.count) { _ in
                                    boundaryY = geo.frame(in: .global).minY
                                }
                        } : nil
                )
                .environmentObject(tabManager)

                // 탭들 사이의 구분선 영역 (마지막 탭 제외)
                if index < tabManager.unpinnedTabs.count - 1 {
                    TabDividerView(
                        tabId: tab.id,
                        draggingTab: $draggingTab,
                        dragLocation: $dragLocation,
                        dropTargetId: $dropTargetId,
                        dropTargetAbove: $dropTargetAbove
                    )
                }
            }

            // [+] 새 탭 버튼 (unpinnedTabs 바로 아래)
            Button(action: {
                tabManager.createTab()
            }, label: {
                HStack {
                    Image(systemName: "plus")
                        .foregroundColor(.white.opacity(0.6))
                    Text("New Tab")
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            })
            .buttonStyle(.plain)
            .background(Color.clear)
            .cornerRadius(6)
            Spacer()
        }
        .frame(minWidth: 200)
        .enableInjection()
    }
}

/// 개별 탭 행
struct TabRowView: View {
    let tab: TabViewModel
    @Binding var draggingTab: TabViewModel?
    @Binding var dragLocation: CGPoint?
    @Binding var boundaryY: CGFloat?
    @Binding var dropTargetId: UUID?
    @Binding var dropTargetAbove: Bool
    @EnvironmentObject var tabManager: TabManager
    @GestureState private var dragOffset = CGSize.zero
    @State private var isDropTargetAbove = false
    @State private var isDropTargetBelow = false

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let midY = frame.midY
            let isHovering = (dragLocation?.y ?? -10000) >= frame.minY && (dragLocation?.y ?? -10000) <= frame.maxY
            let isLastPinned = tab.isPinned && (tabManager.pinnedTabs.last?.id == tab.id)
            let isFirstUnpinned = !tab.isPinned && (tabManager.unpinnedTabs.first?.id == tab.id)
            let sameSection = (draggingTab?.isPinned == tab.isPinned)
            let dragY = dragLocation?.y ?? -10000
            // 탭 내용 (구분선 제거)
            tabContent
                .onChange(of: dragLocation) { _ in
                    // 드래그 중 타겟 경계 업데이트 (자기 자신 제외)
                    // dragLocation가 nil로 변하는 시점(제스처 종료)에는 타겟을 유지한다
                    guard let dragLoc = dragLocation, let dragging = draggingTab, dragging.id != tab.id else { return }
                    let dragY = dragLoc.y
                    // 드래그 위치가 탭 영역 내에 있으면 타겟 설정
                    if isHovering {
                        // 다른 탭들의 dropTargetId 초기화
                        dropTargetId = nil
                        dropTargetAbove = false

                        if dragY < midY {
                            dropTargetId = tab.id
                            dropTargetAbove = true
                        } else {
                            dropTargetId = tab.id
                            dropTargetAbove = false
                        }
                    }
                }
        }
        .frame(height: 28)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragLocation)
    }

    private var tabContent: some View {
        HStack {
            // 탭 제목
            Text(tab.title)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            Spacer()

            // 닫기 버튼 (핀된 탭에서는 숨김)
            if !tab.isPinned {
                Button(action: {
                    tabManager.closeTab(id: tab.id)
                }, label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.caption)
                        .frame(width: 16, height: 16)
                })
                .buttonStyle(.plain)
                .opacity(0.7)
                .onHover { _ in
                    // 호버 효과는 나중에 구현
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(
            tab.id == tabManager.selectedTabID
                ? Color.white.opacity(0.1)
                : Color.clear
        )
        .cornerRadius(6)
        .offset(draggingTab?.id == tab.id ? dragOffset : .zero)
        .scaleEffect(draggingTab?.id == tab.id ? 1.05 : 1.0)
        .opacity(draggingTab?.id == tab.id ? 0.8 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: draggingTab?.id == tab.id)
        .contentShape(Rectangle()) // 전체 영역을 클릭 가능하게 만듦
        .onTapGesture {
            tabManager.selectTab(id: tab.id)
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .updating($dragOffset) { value, state, _ in
                    // 드래그 시작
                    if draggingTab == nil {
                        draggingTab = tab
                    }
                    state = value.translation
                    dragLocation = value.location
                }
                .onEnded { value in
                    // 핀 영역이 비어있을 때 구분선 위로 드래그하면 핀 상태로 변경하되, 드롭 타겟에 맞춰 배치
                    if tabManager.pinnedTabs.isEmpty,
                       !tab.isPinned,
                       let boundary = boundaryY
                    {
                        let endY = value.location.y
                        if endY < boundary {
                            tabManager.togglePin(id: tab.id)
                            if let targetId = dropTargetId {
                                if dropTargetAbove {
                                    tabManager.moveTab(id: tab.id, before: targetId)
                                } else {
                                    tabManager.moveTab(id: tab.id, after: targetId)
                                }
                            }
                            draggingTab = nil
                            dragLocation = nil
                            dropTargetId = nil
                            return
                        }
                    }

                    // 섹션 경계 Y가 있으면 우선 섹션 이동 처리
                    if let boundary = boundaryY {
                        let endY = value.location.y
                        if !tab.isPinned, endY < boundary {
                            // 언핀 → 핀: 정확한 위치에 배치
                            tabManager.togglePin(id: tab.id)
                            if let targetId = dropTargetId {
                                if dropTargetAbove {
                                    tabManager.moveTab(id: tab.id, before: targetId)
                                } else {
                                    tabManager.moveTab(id: tab.id, after: targetId)
                                }
                            }
                            draggingTab = nil
                            dragLocation = nil
                            dropTargetId = nil
                            return
                        }
                        if tab.isPinned, endY >= boundary {
                            // 핀 → 언핀: 정확한 위치에 배치
                            tabManager.togglePin(id: tab.id)

                            // 드롭 타겟이 있으면 해당 위치로 이동
                            if let targetId = dropTargetId {
                                if dropTargetAbove {
                                    tabManager.moveTab(id: tab.id, before: targetId)
                                } else {
                                    tabManager.moveTab(id: tab.id, after: targetId)
                                }
                            }

                            draggingTab = nil
                            dragLocation = nil
                            dropTargetId = nil
                            return
                        }
                    }

                    // 같은 섹션 내 이동: 명시적 타겟이 있을 때만 이동
                    if let target = dropTargetId {
                        if dropTargetAbove {
                            tabManager.moveTab(id: tab.id, before: target)
                        } else {
                            tabManager.moveTab(id: tab.id, after: target)
                        }
                    }

                    // 드래그 종료
                    draggingTab = nil
                    dragLocation = nil
                    dropTargetId = nil
                }
        )
        .contextMenu {
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                tabManager.togglePin(id: tab.id)
            }

            Button("Duplicate Tab") {
                tabManager.duplicateTab(id: tab.id)
            }

            Divider()

            Button("Close Tab") {
                tabManager.closeTab(id: tab.id)
            }
        }
    }

    private func handleDrop(value: DragGesture.Value) {
        // TabManager에 드래그 앤 드롭 로직 위임
        tabManager.handleTabDragDrop(draggedTabId: tab.id, translation: value.translation)
    }
}

struct TabDividerView: View {
    let tabId: UUID
    @Binding var draggingTab: TabViewModel?
    @Binding var dragLocation: CGPoint?
    @Binding var dropTargetId: UUID?
    @Binding var dropTargetAbove: Bool
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 2)
            .background(
                // 드롭 타겟일 때 파란색 구분선 표시
                dropTargetId == tabId ? Color.blue : Color.clear
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dropTargetId)
            .onTapGesture {
                // 구분선 영역 클릭 시 해당 위치에 탭 삽입
                if let dragging = draggingTab {
                    // TODO: 탭 이동 로직
                }
            }
    }
}
