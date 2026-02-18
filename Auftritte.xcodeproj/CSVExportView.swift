//
//  CSVExportView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 18.02.2026.
//

import SwiftUI
import SwiftData

// MARK: - Export View

struct CSVExportView: View {
    @Environment(\.dismiss) private var dismiss

    let keynotes: [Keynote]

    @State private var phase: ExportPhase = .idle
    private let exporter = CSVExporter()

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle:
                    idleView
                case .exporting:
                    exportingView
                case .ready(let url):
                    readyView(url: url)
                case .failed(let message):
                    failedView(message: message)
                }
            }
            .navigationTitle("CSV exportieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await buildExport()
        }
    }

    // MARK: - Idle / Generating

    private var idleView: some View {
        exportingView
    }

    private var exportingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("CSV wird erstellt…")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Ready Phase

    private func readyView(url: URL) -> some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("CSV bereit")
                    .font(.title2.bold())
                Text("\(keynotes.count) Auftritt\(keynotes.count == 1 ? "" : "e") exportiert.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                // ShareLink teilt die fertige Datei direkt
                ShareLink(
                    item: url,
                    preview: SharePreview(
                        url.lastPathComponent,
                        image: Image(systemName: "tablecells")
                    )
                ) {
                    Label("Teilen / Speichern", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)

                Button("Fertig") {
                    dismiss()
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            // Dateiinfo
            GroupBox {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.caption.monospaced())
                        Text(fileSizeLabel(for: url))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Failed Phase

    private func failedView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Export fehlgeschlagen")
                    .font(.title2.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Erneut versuchen") {
                Task { await buildExport() }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    // MARK: - Export Logic

    private func buildExport() async {
        phase = .exporting
        do {
            let url = try await exporter.exportToFile(keynotes)
            phase = .ready(url: url)
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func fileSizeLabel(for url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Export Phase

private enum ExportPhase {
    case idle
    case exporting
    case ready(url: URL)
    case failed(message: String)
}

// MARK: - Preview

#Preview {
    CSVExportView(keynotes: [])
        .modelContainer(for: Keynote.self, inMemory: true)
}
