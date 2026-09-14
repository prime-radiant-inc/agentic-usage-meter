import AppKit
import SwiftUI

public struct MenuBarContentView: View {
    private let model: AppModel
    private let updateController: AppUpdateController
    @State private var maximumHeight = Self.availableHeight
    @Environment(\.openSettings) private var openSettings

    public init(
        model: AppModel,
        updateController: AppUpdateController = .disabled,
    ) {
        self.model = model
        self.updateController = updateController
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Usage")
                    .font(.title3.weight(.semibold))
                if model.isSampleData {
                    SampleDataBadge(label: "SAMPLE DATA")
                }
                Spacer()
                Button {
                    refreshAllAccounts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh eligible accounts")
                .disabled(model.accounts.contains {
                    $0.isRefreshing
                })
            }
            .controlSize(.small)
            .padding(
                .horizontal,
                UsageTimelineMetrics.outerHorizontalPadding
            )
            .padding(
                .vertical,
                UsageTimelineMetrics.outerVerticalPadding
            )

            Divider()

            ViewThatFits(in: .vertical) {
                timeline
                    .fixedSize(
                        horizontal: false,
                        vertical: true,
                    )
                ScrollView {
                    timeline
                }
            }

            Divider()

            HStack {
                Button {
                    Task {
                        try? await model.setFloatingWidgetVisible(
                            !model.isFloatingWidgetVisible,
                        )
                    }
                } label: {
                    Label(
                        model.isFloatingWidgetVisible
                            ? "Hide Widget"
                            : "Show Widget",
                        systemImage: "rectangle.on.rectangle",
                    )
                }

                Spacer()

                if updateController.canCheckForUpdates {
                    Button {
                        updateController.checkForUpdates()
                    } label: {
                        Label(
                            "Check for Updates…",
                            systemImage: "arrow.down.circle",
                        )
                    }
                }

                Button {
                    SettingsWindowPresenter().present {
                        openSettings()
                    }
                } label: {
                    Label("Settings", systemImage: "gear")
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(
                .horizontal,
                UsageTimelineMetrics.outerHorizontalPadding
            )
            .padding(
                .vertical,
                UsageTimelineMetrics.outerVerticalPadding
            )
        }
        .frame(width: UsageTimelineMetrics.naturalWidth)
        .frame(maxHeight: maximumHeight)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            maximumHeight = Self.availableHeight
        }
    }

    private static var availableHeight: CGFloat {
        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        // Leave room for the menu panel's border and spacing below the menu bar.
        return max(1, (screen?.visibleFrame.height ?? 600) - 16)
    }

    private func refreshAllAccounts() {
        Task {
            await model.refreshAllAccounts()
        }
    }

    private var timeline: some View {
        UsageTimelineView(
            accounts: model.accounts,
            collapsedSections:
                model.collapsedUsageSections,
            onToggleSection: { section in
                Task {
                    try? await model.toggleUsageSection(
                        section,
                    )
                }
            },
            onOpenAccount: {
                AccountDashboardPresenter.shared.open($0)
            }
        )
            .padding(
                .horizontal,
                UsageTimelineMetrics.outerHorizontalPadding
            )
            .padding(
                .vertical,
                UsageTimelineMetrics.outerVerticalPadding
            )
    }

}
