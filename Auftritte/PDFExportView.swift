//
//  PDFExportView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 18.02.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct PDFExportView: View {
    let keynotes: [Keynote]

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = "Auftrittsübersicht"
    @State private var isExporting = false
    @State private var showFileExporter = false
    @State private var exportError: String?
    @State private var pdfDocument: PDFFile?

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

        pdfDocument = PDFFile(data: pdfData)
        showFileExporter = true
    }
}

/// A `FileDocument` wrapper so SwiftUI's fileExporter can handle raw PDF data.
struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = fileData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
