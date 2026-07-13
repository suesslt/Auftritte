//
//  ContentView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import SwiftUI
import SwiftData
import ScoreUI
import QuickLook

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Keynote.eventDate, order: .forward) private var keynotes: [Keynote]

    @State private var searchText = ""
    @State private var selectedKeynote: Keynote?
    @State private var newKeynoteID: PersistentIdentifier?
    @State private var selectedCategory: SidebarCategory? = .alleAuftritte
    @State private var statusFilter: KeynoteStatus?
    @State private var showingStats = false
    @State private var pdfURL: URL?
    @State private var showingCSVImport = false
    @State private var showingCSVExport = false
    @State private var showingDeleteAllConfirmation = false
    @State private var showingSettings = false
    @State private var viewMode: ViewMode = .list
    @StateObject private var calendarService = CalendarService()
    @StateObject private var errorHandler = ErrorHandler()

    enum ViewMode: String, CaseIterable, Identifiable {
        case list = "Liste"
        case table = "Tabelle"
        var id: Self { self }
        var icon: String {
            switch self {
            case .list:  return "list.bullet"
            case .table: return "tablecells"
            }
        }
    }

    var filteredKeynotes: [Keynote] {
        var filtered = keynotes

        if let category = selectedCategory {
            switch category {
            case .alleAuftritte:
                break // alle ohne Einschränkung
            case .pendenzSpeaker:
                filtered = filtered.filter { $0.pendenz == .speaker && !$0.pendenzErledigt }
            case .datumUngeklaert:
                filtered = filtered.filter { $0.inAbklaerung && $0.status != .cancelled }
            case .vereinbarteAuftritte:
                filtered = filtered.filter { !$0.inAbklaerung && $0.eventDate >= Date() && $0.status != .cancelled }
            case .durchgefuehrt:
                filtered = filtered.filter { $0.section == .erledigt }
            }
        }

        if let status = statusFilter {
            filtered = filtered.filter { $0.status == status }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { keynote in
                keynote.eventName.localizedCaseInsensitiveContains(searchText) ||
                keynote.keynoteTitle.localizedCaseInsensitiveContains(searchText) ||
                keynote.keynoteTheme.localizedCaseInsensitiveContains(searchText) ||
                keynote.clientOrganization.localizedCaseInsensitiveContains(searchText) ||
                keynote.location.localizedCaseInsensitiveContains(searchText) ||
                keynote.contactFirstName.localizedCaseInsensitiveContains(searchText) ||
                keynote.contactLastName.localizedCaseInsensitiveContains(searchText) ||
                keynote.contactFullName.localizedCaseInsensitiveContains(searchText) ||
                keynote.contactEmail.localizedCaseInsensitiveContains(searchText) ||
                keynote.contactPhone.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    private var groupedKeynotes: [(section: KeynoteSection, keynotes: [Keynote])] {
        let grouped = Dictionary(grouping: filteredKeynotes) { $0.section }
        return KeynoteSection.allCases.compactMap { section in
            guard let items = grouped[section], !items.isEmpty else { return nil }
            return (section: section, keynotes: items.sorted { $0.eventDate < $1.eventDate })
        }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar — nur Kategorie-Filter
            List(selection: $selectedCategory) {
                ForEach(SidebarCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .font(.title3)
                        .tag(category)
                }
            }
            .navigationTitle("Auftritte")
        } detail: {
            NavigationStack {
                keynoteListOrTable
                    .navigationTitle(selectedCategory?.rawValue ?? "Auftritte")
                    .searchable(text: $searchText, prompt: "Suchen...")
                    .toolbar { mainToolbar }
                    .navigationDestination(item: $selectedKeynote) { keynote in
                        KeynoteDetailView(
                            keynote: keynote,
                            isNewKeynote: keynote.persistentModelID == newKeynoteID,
                            onCancel: { handleEditorCancel(for: keynote) },
                            onSave: {
                                newKeynoteID = nil
                                selectedKeynote = nil
                            }
                        )
                    }
                    .sheet(isPresented: $showingStats) {
                        NavigationStack {
                            KeynoteStatsView()
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Fertig") { showingStats = false }
                                    }
                                }
                        }
                    }
                    .sheet(isPresented: $showingSettings) {
                        SettingsView()
                    }
                    .sheet(isPresented: $showingCSVImport) {
                        CSVImportView()
                    }
                    .sheet(isPresented: $showingCSVExport) {
                        CSVExportView(keynotes: filteredKeynotes)
                    }
                    .sheet(isPresented: $showingDeleteAllConfirmation) {
                        DeleteAllConfirmationView(
                            count: keynotes.count,
                            onConfirm: { deleteAllKeynotes() }
                        )
                    }
                    .quickLookPreview($pdfURL)
            }
        }
        .task {
            _ = await calendarService.requestAccess()
        }
        .errorAlert(errorHandler: errorHandler)
        .onChange(of: selectedCategory) { _, _ in selectedKeynote = nil }
        .onChange(of: statusFilter) { _, _ in selectedKeynote = nil }
        .onChange(of: selectedKeynote) { oldValue, newValue in
            // Wenn der Editor für eine frisch erstellte, noch unverwendete Keynote geschlossen wird, löschen
            guard let old = oldValue, old.persistentModelID != newValue?.persistentModelID else { return }
            if old.persistentModelID == newKeynoteID, isDraftKeynote(old) {
                modelContext.delete(old)
                newKeynoteID = nil
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Ansicht", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: createNewKeynote) {
                Label("Neuer Auftritt", systemImage: "plus")
            }
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Button(action: { statusFilter = nil }) {
                    Label("Alle", systemImage: statusFilter == nil ? "checkmark" : "")
                }
                Divider()
                ForEach(KeynoteStatus.allCases) { status in
                    Button(action: { statusFilter = status }) {
                        HStack {
                            Circle()
                                .fill(status.color)
                                .frame(width: 12, height: 12)
                            Text(status.rawValue)
                            if statusFilter == status {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Button(action: { showingStats = true }) {
                    Label("Statistiken", systemImage: "chart.bar.fill")
                }
                Button(action: { exportPDF() }) {
                    Label("Statistik Report", systemImage: "doc.fill")
                }
                Button(action: { exportFahrtenPDF() }) {
                    Label("Steuerabzüge Fahrten", systemImage: "car.fill")
                }
                Divider()
                Button(action: { showingCSVImport = true }) {
                    Label("CSV importieren", systemImage: "square.and.arrow.down.on.square")
                }
                Button(action: { showingCSVExport = true }) {
                    Label("CSV exportieren", systemImage: "square.and.arrow.up.on.square")
                }
                Divider()
                Button(action: { showingSettings = true }) {
                    Label("Einstellungen", systemImage: "gearshape")
                }
                Divider()
                Button(role: .destructive) {
                    showingDeleteAllConfirmation = true
                } label: {
                    Label("Alle Auftritte löschen", systemImage: "trash.fill")
                }
            } label: {
                Label("Mehr", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Liste / Tabelle

    @ViewBuilder
    private var keynoteListOrTable: some View {
        switch viewMode {
        case .list:
            keynoteList
        case .table:
            AuftritteTableView(
                keynotes: filteredKeynotes,
                selection: $selectedKeynote,
                onUpdateStatus: updateStatus,
                onDelete: deleteKeynote,
                mode: selectedCategory == .pendenzSpeaker ? .pendenzen : .standard
            )
        }
    }

    private var keynoteList: some View {
        List {
            if selectedCategory == .alleAuftritte || selectedCategory == .vereinbarteAuftritte {
                ForEach(filteredKeynotes) { keynote in
                    keynoteRow(for: keynote)
                }
            } else {
                ForEach(groupedKeynotes, id: \.section) { group in
                    Section(group.section.title) {
                        ForEach(group.keynotes) { keynote in
                            keynoteRow(for: keynote)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func keynoteRow(for keynote: Keynote) -> some View {
        Button {
            selectedKeynote = keynote
        } label: {
            KeynoteRowView(keynote: keynote)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteKeynote(keynote)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Menu {
                ForEach(KeynoteStatus.allCases) { status in
                    Button {
                        updateStatus(for: keynote, to: status)
                    } label: {
                        HStack {
                            Circle()
                                .fill(status.color)
                                .frame(width: 12, height: 12)
                            Text(status.rawValue)
                            if keynote.status == status {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Status", systemImage: "circle.fill")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                selectedKeynote = keynote
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }

            Button(role: .destructive) {
                deleteKeynote(keynote)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func createNewKeynote() {
        let keynote = Keynote()
        modelContext.insert(keynote)
        newKeynoteID = keynote.persistentModelID
        selectedKeynote = keynote
    }

    private func handleEditorCancel(for keynote: Keynote) {
        // Cancel wird nur für neue Keynotes ausgelöst → immer löschen
        if keynote.persistentModelID == newKeynoteID {
            modelContext.delete(keynote)
        }
        newKeynoteID = nil
        selectedKeynote = nil
    }

    private func isDraftKeynote(_ keynote: Keynote) -> Bool {
        // Heuristik: noch nicht inhaltlich befüllt
        keynote.eventName.isEmpty &&
        keynote.keynoteTitle.isEmpty &&
        keynote.clientOrganization.isEmpty
    }

    private func updateStatus(for keynote: Keynote, to status: KeynoteStatus) {
        withAnimation {
            keynote.status = status
        }
    }

    private func deleteKeynote(_ keynote: Keynote) {
        withAnimation {
            if selectedKeynote?.persistentModelID == keynote.persistentModelID {
                selectedKeynote = nil
            }
            if keynote.persistentModelID == newKeynoteID {
                newKeynoteID = nil
            }

            if let eventID = keynote.calendarEventID {
                Task {
                    try? await calendarService.deleteEvent(eventID: eventID)
                }
            }
            modelContext.delete(keynote)
        }
    }

    private func deleteAllKeynotes() {
        selectedKeynote = nil
        newKeynoteID = nil
        for keynote in keynotes {
            modelContext.delete(keynote)
        }
        showingDeleteAllConfirmation = false
    }

    private func exportPDF() {
        let pdfData = KeynotePDFGenerator.generatePDF(
            keynotes: Array(keynotes),
            title: "Auftrittsübersicht"
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Auftrittsübersicht.pdf")
        try? pdfData.write(to: tempURL)
        pdfURL = tempURL
    }

    private func exportFahrtenPDF() {
        let pdfData = FahrtenPDFGenerator.generatePDF(
            keynotes: Array(keynotes),
            kilometerpreisCHF: AppSettings.kilometerpreis
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Steuerabzüge Fahrten.pdf")
        try? pdfData.write(to: tempURL)
        pdfURL = tempURL
    }
}

// MARK: - Keynote Row View
struct KeynoteRowView: View {
    let keynote: Keynote

    var body: some View {
        KeynoteListItemView(
            keynote: keynote,
            contactName: keynote.contactHasData ? keynote.contactDisplayName : nil
        )
        .foregroundColor(.primary)
    }
}

// MARK: - Delete-All Bestätigung

private struct DeleteAllConfirmationView: View {
    let count: Int
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText: String = ""

    private static let confirmationPhrase = "Auftritte"

    private var canDelete: Bool {
        confirmationText.trimmingCharacters(in: .whitespaces) == Self.confirmationPhrase
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        "Diese Aktion löscht alle \(count) Auftritte unwiderruflich aus dieser App. Kalender-Einträge bleiben erhalten.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }

                Section("Bestätigung") {
                    Text("Geben Sie zur Bestätigung '\(Self.confirmationPhrase)' ein:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField(Self.confirmationPhrase, text: $confirmationText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Alle Auftritte löschen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Löschen", role: .destructive) {
                        onConfirm()
                    }
                    .disabled(!canDelete)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(previewContainer())
}
