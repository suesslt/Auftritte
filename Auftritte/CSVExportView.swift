//
//  CSVExportView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 18.02.2026.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Export View

struct CSVExportView: View {
    @Environment(\.dismiss) private var dismiss

    let keynotes: [Keynote]

    @State private var phase: ExportPhase = .building

    private let exporter = CSVExporter()

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .building:
                    buildingView

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
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .task { await buildExport() }
    }

    // MARK: - Building Phase

    private var buildingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("CSV wird erstellt…").foregroundStyle(.secondary)
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
                // Der Button dient gleichzeitig als Popover-Anker auf dem iPad
                ShareButton(url: url, onShared: { dismiss() })

                Button("Fertig") { dismiss() }
            }

            Spacer()

            // Dateiinfo
            GroupBox {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text").foregroundStyle(.tint)
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
                Text("Export fehlgeschlagen").font(.title2.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Erneut versuchen") {
                phase = .building
                Task { await buildExport() }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    // MARK: - Logic

    private func buildExport() async {
        do {
            let url = try await exporter.exportToDocuments(keynotes)
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
    case building
    case ready(url: URL)
    case failed(message: String)
}

// MARK: - Share Button (iPad-kompatibel)
//
// Reiner SwiftUI-Button mit UIViewControllerRepresentable-Helfer
// für das UIActivityViewController-Popover.

private struct ShareButton: View {
    let url: URL
    var onShared: (() -> Void)? = nil
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Label("Teilen / Speichern", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .background {
            // Unsichtbarer Anker-View, der den UIActivityViewController präsentiert
            SharePresenter(url: url, isPresented: $showSheet, onShared: onShared)
                .frame(width: 0, height: 0)
        }
    }
}

// Präsentiert UIActivityViewController mit korrektem iPad-Popover-Anker
private struct SharePresenter: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    var onShared: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented, uiViewController.presentedViewController == nil else { return }

        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        // Mindestgrösse für das Sheet (wirkt sich vor allem auf iPad aus)
        vc.preferredContentSize = CGSize(width: 540, height: 620)

        if let popover = vc.popoverPresentationController {
            popover.sourceView = uiViewController.view
            popover.sourceRect = CGRect(
                x: uiViewController.view.bounds.midX,
                y: uiViewController.view.bounds.midY,
                width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }

        vc.completionWithItemsHandler = { _, completed, _, _ in
            isPresented = false
            if completed {
                onShared?()
            }
        }

        uiViewController.present(vc, animated: true)
    }
}

// MARK: - Preview

#Preview {
    CSVExportView(keynotes: [])
        .modelContainer(for: Keynote.self, inMemory: true)
}
