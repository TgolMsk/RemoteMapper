import AppKit
import RemoteKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.controlActiveState) private var activeState

    static let stageWidth: CGFloat = 440

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            StageView()
                .frame(width: Self.stageWidth)
            Rectangle().fill(.black.opacity(0.5)).frame(width: 1)
            VStack(spacing: 0) {
                SettingsHeader()
                    .padding(.horizontal, 32)
                    .frame(height: 76, alignment: .bottom)
                    .padding(.bottom, 4)
                Group {
                    switch model.tab {
                    case .mapping: MappingPane()
                    case .general: GeneralPane()
                    case .diagnostics: DiagnosticsPane()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Theme.paneBackground)
        }
        .ignoresSafeArea()
        .frame(minWidth: 1040, minHeight: 700)
        .sheet(item: $model.editor) { context in
            ActionEditorSheet(context: context)
                .environment(model)
        }
        .onChange(of: activeState, initial: true) { _, state in
            model.isSettingsKey = state == .key
        }
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear {
            model.isSettingsKey = false
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// 顶部：分页切换与总开关
struct SettingsHeader: View {
    @Environment(AppModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    let isSelected = model.tab == tab
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { model.tab = tab }
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Theme.card)
                                        .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                                        .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 0.5))
                                        .matchedGeometryEffect(id: "tab", in: namespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Theme.subtleFill, in: .capsule)

            Spacer()

            MasterSwitch()
        }
    }
}

struct MasterSwitch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(model.config.isEnabled ? "映射运行中" : "映射已暂停")
                    .font(.system(size: 12, weight: .semibold))
                Text(model.config.isEnabled ? "当前配置：\(model.activeProfile.name)" : "遥控器保持系统默认行为")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Toggle("启用映射", isOn: $model.config.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.accent)
        }
    }
}
