import Foundation
import SwiftUI

struct LCStorageManagementView: View {
    @EnvironmentObject private var sharedModel: SharedModel
    @StateObject private var model = LCStorageManagementModel()
    @State private var refreshed: Bool = false

    var body: some View {
        Form {
            LCStorageSummarySection(
                breakdown: model.breakdown,
                isCalculating: model.isCalculating,
                errorInfo: model.errorInfo
            )
            if model.isCalculating && model.scannedItems > 0 {
                Section { Text("Scanned \(model.scannedItems.formatted()) items…").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }
            Section {
                NavigationLink { LCDataManagementView() } label: { Text("lc.settings.dataManagement".loc) }
            }
            if model.skippedEntries > 0 { Section { Text("Some files changed or could not be read during the scan. Totals may exclude them; tap Recalculate to retry.").font(.caption).foregroundStyle(.secondary) } }
            if let date = model.lastCalculated { Section { Text("Last calculated: " + date.formatted()).font(.caption).foregroundStyle(.secondary) } }
            LCInstalledAppsSection(breakdown: model.breakdown)
        }
        .navigationTitle("lc.settings.storageManagement".loc)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Recalculate") { Task { await model.refresh(apps: sharedModel.apps, hiddenApps: sharedModel.hiddenApps, force: true) } }.disabled(model.isCalculating) } }
        .onChange(of: sharedModel.isHiddenAppUnlocked) { _ in model.clearForPrivacyChange(); Task { await refresh() } }
        .task {
            if !refreshed {
                await refresh()
                refreshed = true
            }

        }
    }

    private func refresh() async {
        await model.refresh(apps: sharedModel.apps, hiddenApps: sharedModel.hiddenApps)
    }
}
