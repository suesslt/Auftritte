//
//  CSVImportView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 18.02.2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Import View

struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Import-Zustand
    @State private var phase: ImportPhase = .idle
    @State private var importResult: CSVImportResult? = nil
    @State private var importError: String? = nil
    
    // Optionen
    @State private var skipDuplicates = true
    @State private var selectedRowIDs: Set<UUID> = []
    
    // Datei-Picker
    @State private var showingFilePicker = false
    
    private let importer = CSVImporter()
    
    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle:
                    idleView
                case .parsing:
                    parsingView
                case .preview:
                    if let result = importResult {
                        previewView(result: result)
                    }
                case .importing:
                    importingView
                case .done(let count):
                    doneView(count: count)
                case .failed(let message):
                    failedView(message: message)
                }
            }
            .navigationTitle("CSV importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFilePicker(result: result)
        }
    }
    
    // MARK: - Idle Phase
    
    private var idleView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            
            VStack(spacing: 8) {
                Text("CSV importieren")
                    .font(.title2.bold())
                Text("Importiere Auftritte aus einer CSV-Datei im Auftritte-Exportformat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("CSV-Datei wählen", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                
                Toggle("Duplikate überspringen", isOn: $skipDuplicates)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            // Format-Beschreibung
            GroupBox("Erwartetes Format") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(expectedColumns, id: \.self) { col in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                            Text(col)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    
    // MARK: - Parsing Phase
    
    private var parsingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Datei wird analysiert…")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Preview Phase
    
    private func previewView(result: CSVImportResult) -> some View {
        VStack(spacing: 0) {
            // Zusammenfassung
            summaryBanner(result: result)
            
            List(selection: $selectedRowIDs) {
                // Gültige Zeilen
                if !result.validRows.isEmpty {
                    Section {
                        ForEach(result.validRows) { row in
                            ImportRowView(row: row, isSelected: selectedRowIDs.contains(row.id))
                                .tag(row.id)
                        }
                    } header: {
                        Text("Importierbar (\(result.validRows.count))")
                    }
                }
                
                // Fehlerhafte Zeilen
                if !result.invalidRows.isEmpty {
                    Section {
                        ForEach(result.invalidRows) { row in
                            ImportRowView(row: row, isSelected: false)
                        }
                    } header: {
                        Text("Fehlerhaft (\(result.invalidRows.count)) – werden übersprungen")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            
            // Import-Button
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button("Alle auswählen") {
                        selectedRowIDs = Set(result.validRows.map { $0.id })
                    }
                    .font(.subheadline)
                    
                    Spacer()
                    
                    Button {
                        startImport(result: result)
                    } label: {
                        Label(
                            "Importieren (\(selectedRowIDs.count))",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedRowIDs.isEmpty)
                }
                .padding()
            }
        }
        .onAppear {
            // Standardmässig alle gültigen Zeilen auswählen
            selectedRowIDs = Set(result.validRows.map { $0.id })
        }
    }
    
    // MARK: - Summary Banner
    
    private func summaryBanner(result: CSVImportResult) -> some View {
        HStack(spacing: 16) {
            SummaryChip(
                count: result.validRows.count,
                label: "OK",
                color: .green,
                icon: "checkmark.circle.fill"
            )
            SummaryChip(
                count: result.invalidRows.count,
                label: "Fehler",
                color: .red,
                icon: "exclamationmark.triangle.fill"
            )
            SummaryChip(
                count: result.rows.count,
                label: "Total",
                color: .blue,
                icon: "list.bullet"
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Importing Phase
    
    private var importingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Auftritte werden importiert…")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Done Phase
    
    private func doneView(count: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                Text("Import abgeschlossen")
                    .font(.title2.bold())
                Text("\(count) Auftritt\(count == 1 ? "" : "e") erfolgreich importiert.")
                    .foregroundStyle(.secondary)
            }
            
            Button("Fertig") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
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
                Text("Import fehlgeschlagen")
                    .font(.title2.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Erneut versuchen") {
                phase = .idle
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func handleFilePicker(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            phase = .failed(message: error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            parseFile(at: url)
        }
    }
    
    private func parseFile(at url: URL) {
        phase = .parsing
        
        Task {
            // Security-scoped resource für Files aus der Files-App
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            
            do {
                let csvText = try String(contentsOf: url, encoding: .utf8)
                let result = try await importer.parse(csvText)
                
                await MainActor.run {
                    importResult = result
                    phase = .preview
                }
            } catch {
                await MainActor.run {
                    phase = .failed(message: error.localizedDescription)
                }
            }
        }
    }
    
    private func startImport(result: CSVImportResult) {
        phase = .importing
        
        let rowsToImport = result.validRows.filter { selectedRowIDs.contains($0.id) }
        
        Task {
            await MainActor.run {
                var importedCount = 0
                
                for row in rowsToImport {
                    guard let keynote = row.keynote else { continue }
                    
                    // Duplikatsprüfung anhand von eventName + eventDate
                    if skipDuplicates {
                        let existingKeynotes = try? modelContext.fetch(
                            FetchDescriptor<Keynote>()
                        )
                        let isDuplicate = existingKeynotes?.contains { existing in
                            existing.eventName == keynote.eventName &&
                            Calendar.current.isDate(existing.eventDate, equalTo: keynote.eventDate, toGranularity: .minute)
                        } ?? false
                        
                        if isDuplicate { continue }
                    }
                    
                    modelContext.insert(keynote)
                    importedCount += 1
                }
                
                try? modelContext.save()
                phase = .done(count: importedCount)
            }
        }
    }
    
    // MARK: - Hilfsdaten
    
    private var expectedColumns: [String] {
        [
            "eventName (Pflicht)",
            "eventDate (Pflicht, ISO 8601)",
            "keynoteTitle, keynoteTheme, duration",
            "clientOrganization, agreedFeeInCents",
            "targetAudience, location, language",
            "statusRaw, requestDate, notes",
            "contactFullName, contactEmail, contactPhone"
        ]
    }
}

// MARK: - Import Phase

private enum ImportPhase {
    case idle
    case parsing
    case preview
    case importing
    case done(count: Int)
    case failed(message: String)
}

// MARK: - Import Row View

private struct ImportRowView: View {
    let row: CSVImportRow
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.rawEventName)
                    .font(.body)
                    .lineLimit(1)
                
                if let error = row.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let keynote = row.keynote {
                    HStack(spacing: 8) {
                        Text(keynote.eventDate.formatted(date: .abbreviated, time: .omitted))
                        
                        if !keynote.clientOrganization.isEmpty {
                            Text("·")
                            Text(keynote.clientOrganization)
                        }
                        
                        if !keynote.contactFullName.isEmpty {
                            Text("·")
                            Text(keynote.contactFullName)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            
            Spacer()
            
            if row.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .opacity(row.error != nil ? 0.5 : 1.0)
    }
}

// MARK: - Summary Chip

private struct SummaryChip: View {
    let count: Int
    let label: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    CSVImportView()
        .modelContainer(for: Keynote.self, inMemory: true)
}
