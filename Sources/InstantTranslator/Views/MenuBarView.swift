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
        GeometryReader { geometry in
            VStack(spacing: 12) {
                header

                ScrollView {
                    VStack(spacing: 12) {
                        StatusSection(licenseService: licenseService)
                        PreferencesSection(settingsVM: viewModel.settingsVM)
                        BehaviorSection(
                            settingsVM: viewModel.settingsVM,
                            translatorVM: viewModel
                        )
                    }
                    .frame(width: max(0, geometry.size.width - 24), alignment: .topLeading)
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
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(Color.clear)
            .sheet(isPresented: $updateService.isShowingManualUpdateFallback) {
                UpdateFailureSheet(updateService: updateService)
            }
        }
        .frame(width: 336, height: 560)
        .background(Color.clear)
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
