import ControlVCore
import SwiftUI

struct HistoryTabView: View {
    @State private var entries: [HistoryEntry] = []

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Translations from the app and Share Extension will appear here.")
                    )
                } else {
                    List {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.translated)
                                    .font(.body)
                                    .lineLimit(3)
                                Text(entry.source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                HStack {
                                    Text("\(entry.language.rawValue) · \(entry.tone.rawValue)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(entry.timestamp, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .leading) {
                                Button {
                                    UIPasteboard.general.string = entry.translated
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                HistoryStore.shared.remove(id: entries[index].id)
                            }
                            entries = HistoryStore.shared.all()
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) {
                            HistoryStore.shared.clear()
                            entries = []
                        }
                    }
                }
            }
            .onAppear {
                entries = HistoryStore.shared.all()
            }
        }
    }
}
