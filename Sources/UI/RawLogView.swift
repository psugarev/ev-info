import SwiftUI
import SwiftData

// MARK: - Raw Log View
// Displays raw OBD frames from a trip for diagnostics and PID discovery.
// Essential per RESEARCH.md workflow: capture → correlate → validate.

struct RawLogView: View {
    let tripID: UUID?

    /// Frames are fetched newest-first with a hard cap (and filtered by trip in
    /// the store), so opening the log never loads the whole table into memory.
    private static let fetchLimit = 2_000

    @Query private var baseFrames: [RawOBDFrame]
    @State private var filterText = ""

    init(tripID: UUID?) {
        self.tripID = tripID
        var descriptor = FetchDescriptor<RawOBDFrame>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let tripID {
            let optionalID: UUID? = tripID
            descriptor.predicate = #Predicate { $0.tripID == optionalID }
        }
        descriptor.fetchLimit = Self.fetchLimit
        _baseFrames = Query(descriptor)
    }

    private var frames: [RawOBDFrame] {
        guard !filterText.isEmpty else { return Array(baseFrames.prefix(500)) }
        return baseFrames.filter {
            $0.request.localizedCaseInsensitiveContains(filterText) ||
            $0.response.localizedCaseInsensitiveContains(filterText)
        }.prefix(500).map { $0 }
    }

    /// CSV is portable and keeps the original request/response text intact for
    /// later decoder work. Limit a single share to avoid an oversized sheet.
    private var exportText: String {
        let formatter = ISO8601DateFormatter()
        let rows = baseFrames.prefix(5_000).map { frame in
            [
                formatter.string(from: frame.timestamp),
                frame.tripID?.uuidString ?? "",
                frame.request,
                frame.response
            ]
            .map(csvField)
            .joined(separator: ",")
        }
        return (["timestamp,trip_id,request,response"] + rows).joined(separator: "\n")
    }

    private func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\"").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n"))\""
    }

    var body: some View {
        Group {
            if frames.isEmpty {
                ContentUnavailableView(
                    "No Frames",
                    systemImage: "waveform",
                    description: Text("OBD frames will appear here during a trip.")
                )
            } else {
                List(frames, id: \.id) { frame in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(frame.request)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.blue)
                            Spacer()
                            Text(frame.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(frame.response
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\r", with: " "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
                .searchable(text: $filterText, prompt: "Filter by PID or response")
            }
        }
        .navigationTitle("Raw OBD Log")
        .toolbar {
            if !baseFrames.isEmpty {
                ShareLink(
                    item: exportText,
                    subject: Text("EV Info Raw OBD Log"),
                    message: Text("Read-only OBD capture exported from EV Info as CSV (latest 2,000 frames).")
                ) {
                    Label("Share Raw Log", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
