import SwiftUI

@MainActor
struct MenuBarView: View {
    @Bindable var viewModel: TranslatorViewModel
    @Bindable var licenseService: LicenseService
    @Bindable var updateService: UpdateService
    let onOpenFeedback: () -> Void
    let onCheckForUpdates: () -> Void
    let onShowAbout: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            header

            ScrollView {
                VStack(spacing: 8) {
                    StatusSection(licenseService: licenseService)
                    PreferencesSection(settingsVM: viewModel.settingsVM)
                    BehaviorSection(
                        settingsVM: viewModel.settingsVM,
                        translatorVM: viewModel,
                        updateService: updateService
                    )
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)

            FooterSection(
                translatorVM: viewModel,
                updateService: updateService,
                onOpenFeedback: onOpenFeedback,
                onCheckForUpdates: onCheckForUpdates,
                onShowAbout: onShowAbout
            )
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .frame(width: 336)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    MenuTheme.pageLight.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .sheet(isPresented: $updateService.isShowingManualUpdateFallback) {
            UpdateFailureSheet(updateService: updateService)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                BrandMarkView()

                Text("ctrl+v")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            ShortcutBadge(keys: viewModel.settingsVM.shortcutKeyCaps)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
