import ControlVCore
import SwiftUI

struct HistoryTabView: View {
    @State private var entries: [HistoryEntry] = []
    @State private var query = ""
    @State private var showToast = false
    @State private var showClearConfirm = false

    private var filtered: [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.translated.localizedCaseInsensitiveContains(q) || $0.source.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("Nothing translated yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Translations from the app, the Share sheet and the keyboard show up here."))
                } else {
                    List {
                        ForEach(filtered) { entry in
                            HistoryRow(entry: entry) {
                                UIPasteboard.general.string = entry.translated
                                withAnimation { showToast = true }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    HistoryStore.shared.remove(id: entry.id)
                                    entries = HistoryStore.shared.all()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .searchable(text: $query, prompt: "Search translations")
                }
            }
            .background(AuroraBackground())
            .navigationTitle("History")
            .toolbar {
                if !entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { showClearConfirm = true }
                    }
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { HistoryStore.shared.clear(); entries = [] }
            } message: {
                Text("Removes the translations saved on this iPhone. Your Mac isn't affected.")
            }
            .toast("Copied", isPresented: $showToast)
            .onAppear { entries = HistoryStore.shared.all() }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.translated)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(entry.source)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text(entry.language.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.blue)
                    Text("·").foregroundStyle(.tertiary)
                    Text(entry.tone.rawValue).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.timestamp, style: .relative).font(.caption).foregroundStyle(.tertiary)
                    Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(18, interactive: true)
        }
        .buttonStyle(.plain)
    }
}
