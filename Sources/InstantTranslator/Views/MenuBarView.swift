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
        VStack(spacing: 12) {
            header

            ScrollView {
                VStack(spacing: 12) {
                    StatusSection(licenseService: licenseService)
                    PreferencesSection(settingsVM: viewModel.settingsVM)
                    BehaviorSection(
                        settingsVM: viewModel.settingsVM,
                        translatorVM: viewModel,
                        updateService: updateService
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            FooterSection(
                translatorVM: viewModel,
                updateService: updateService,
                onOpenFeedback: onOpenFeedback,
                onCheckForUpdates: onCheckForUpdates,
                onShowAbout: onShowAbout
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(width: 336)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .sheet(isPresented: $updateService.isShowingManualUpdateFallback) {
            UpdateFailureSheet(updateService: updateService)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                BrandMarkView()

                Text("ctrl+v")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            ShortcutBadge(keys: viewModel.settingsVM.shortcutKeyCaps)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}
