//
//  PDFExportView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 10.02.2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// View zum Exportieren der Keynote-Liste als PDF
struct PDFExportView: View {
    @Environment(\.dismiss) private var dismiss
    let keynotes: [Keynote]
    
    @State private var documentTitle = "Auftrittsübersicht"
    @State private var showingShareSheet = false
    @State private var pdfData: Data?
    @State private var isGenerating = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("PDF-Einstellungen") {
                    TextField("Dokumenttitel", text: $documentTitle)
                    
                    HStack {
                        Text("Anzahl Auftritte")
                        Spacer()
                        Text("\(keynotes.count)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Sortierung")
                        Spacer()
                        Text("Chronologisch")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section {
                    if isGenerating {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text("PDF wird generiert...")
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                            Spacer()
                        }
                    } else {
                        Button(action: generateAndSharePDF) {
                            Label("PDF generieren und teilen", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("PDF exportieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let pdfData = pdfData {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(documentTitle).pdf")
                    let _ = try? pdfData.write(to: tempURL)
                    return ShareSheet(items: [tempURL])
                } else {
                    return ShareSheet(items: [])
                }
            }
        }
    }
    
    private func generateAndSharePDF() {
        isGenerating = true
        
        Task {
            // Kleine Verzögerung für UI-Feedback
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            let data = KeynotePDFGenerator.generatePDF(
                keynotes: keynotes,
                title: documentTitle,
                generationDate: Date()
            )
            
            pdfData = data
            isGenerating = false
            showingShareSheet = true
        }
    }
}

// MARK: - Preview

#Preview {
    PDFExportView(keynotes: [
        Keynote(
            eventName: "Tech Conference 2026",
            eventDate: Date(),
            keynoteTitle: "Die Zukunft der KI",
            duration: 60,
            clientOrganization: "Tech Corp",
            location: "Zürich",
            status: .contractSigned
        ),
        Keynote(
            eventName: "Leadership Summit",
            eventDate: Date().addingTimeInterval(86400 * 7),
            keynoteTitle: "Agile Führung",
            duration: 90,
            clientOrganization: "Business Leaders AG",
            location: "Bern",
            status: .requested
        )
    ])
}
