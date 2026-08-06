//
//  PDFExportView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 18.02.2026.
//

import ScoreUI
import SwiftUI
import UniformTypeIdentifiers

struct PDFExportView: View {
    let keynotes: [Keynote]

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = "Auftrittsübersicht"
    @State private var isExporting = false
    @State private var showFileExporter = false
    @State private var exportError: String?
    @State private var pdfDocument: DataFileDocument?

    var body: some View {
        NavigationStack {
            Form {
                Section("Dokumenttitel") {
                    TextField("Titel", text: $title)
                }

                Section("Inhalt") {
                    LabeledContent("Auftritte", value: "\(keynotes.count)")
                }

                if let error = exportError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("PDF exportieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Exportieren") {
                        preparePDF()
                    }
                    .disabled(title.isEmpty || isExporting)
                }
            }
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "\(title).pdf"
        ) { result in
            isExporting = false
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                exportError = "Fehler beim Speichern: \(error.localizedDescription)"
            }
        }
    }

    private func preparePDF() {
        isExporting = true
        exportError = nil

        let pdfData = KeynotePDFGenerator.generatePDF(
            keynotes: keynotes,
            title: title
        )

        pdfDocument = DataFileDocument(data: pdfData)
        showFileExporter = true
    }
}

