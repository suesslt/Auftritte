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
    @State private var newKeynote: Keynote?
    @State private var selection: Keynote.ID?
    @State private var selectedCategory: SidebarCategory? = .alleAuftritte
    @State private var statusFilter: KeynoteStatus?
    @State private var showingStats = false
    @State private var pdfURL: URL?
    @State private var showingCSVImport = false
    @State private var showingCSVExport = false
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

        // Kategorie-Filter
        if let category = selectedCategory {
            switch category {
            case .alleAuftritte:
                filtered = filtered.filter { !$0.inAbklaerung }
            case .pendenzSpeaker:
                filtered = filtered.filter { $0.section == .pendenzSpeaker }
            case .datumUngeklaert:
                filtered = filtered.filter { $0.inAbklaerung && $0.eventDate >= Date() && $0.status != .cancelled }
            case .vereinbarteAuftritte:
                filtered = filtered.filter { !$0.inAbklaerung && $0.eventDate >= Date() && $0.status != .cancelled }
            case .durchgefuehrt:
                filtered = filtered.filter { $0.section == .erledigt }
            }
        }

        // Status-Filter
        if let status = statusFilter {
            filtered = filtered.filter { $0.status == status }
        }

        // Suchtext-Filter
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
            // Spalte 1 — Sidebar: Kategorie-Navigation
            List(selection: $selectedCategory) {
                ForEach(SidebarCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .font(.title3)
                        .tag(category)
                }
            }
            .navigationTitle("Auftritte")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createNewKeynote) {
                        Label("Neuer Auftritt", systemImage: "plus")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button(action: { showingStats = true }) {
                            Label("Statistiken", systemImage: "chart.bar.fill")
                        }

                        Button(action: { exportPDF() }) {
                            Label("PDF exportieren", systemImage: "doc.fill")
                        }

                        Divider()

                        Button(action: { showingCSVImport = true }) {
                            Label("CSV importieren", systemImage: "square.and.arrow.down.on.square")
                        }

                        Button(action: { showingCSVExport = true }) {
                            Label("CSV exportieren", systemImage: "square.and.arrow.up.on.square")
                        }
                    } label: {
                        Label("Mehr", systemImage: "ellipsis.circle")
                    }
                }
            }
        } content: {
            // Spalte 2 — Gefilterte Auftritt-Liste oder Tabelle
            Group {
                switch viewMode {
                case .list:
                    keynoteList
                case .table:
                    AuftritteTableView(
                        keynotes: filteredKeynotes,
                        selection: $selection,
                        onUpdateStatus: updateStatus,
                        onDelete: deleteKeynote
                    )
                }
            }
            .navigationTitle(selectedCategory?.rawValue ?? "Auftritte")
            .navigationSplitViewColumnWidth(
                min: 300,
                ideal: viewMode == .table ? 900 : 400,
                max: viewMode == .table ? .infinity : 500
            )
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Suchen...")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Ansicht", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
            }
            .sheet(isPresented: $showingStats) {
                NavigationStack {
                    KeynoteStatsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Fertig") {
                                    showingStats = false
                                }
                            }
                        }
                }
            }
            .quickLookPreview($pdfURL)
            .sheet(isPresented: $showingCSVImport) {
                CSVImportView()
            }
            .sheet(isPresented: $showingCSVExport) {
                CSVExportView(keynotes: filteredKeynotes)
            }
            .onChange(of: filteredKeynotes.map { $0.id }) { oldValue, newValue in
                // Wenn die Selection nicht mehr in der Liste ist, deselektieren
                if let currentSelection = selection,
                   !newValue.contains(currentSelection) {
                    selection = nil
                }
            }
        } detail: {
            if let newKeynote = newKeynote {
                // Neuer Auftritt wird erstellt
                KeynoteDetailView(
                    keynote: newKeynote, 
                    isNewKeynote: true,
                    onCancel: {
                        self.newKeynote = nil
                        self.selection = nil
                    },
                    onSave: {
                        self.newKeynote = nil
                        // Selection bleibt, damit der neue Auftritt ausgewählt ist
                    }
                )
            } else if let selectedID = selection,
                      let keynote = keynotes.first(where: { $0.id == selectedID }) {
                // Bestehender Auftritt wird bearbeitet
                KeynoteDetailView(keynote: keynote, isNewKeynote: false)
            } else {
                ContentUnavailableView(
                    "Wähle einen Auftritt",
                    systemImage: "mic.fill",
                    description: Text("Wähle einen Auftritt aus der Liste oder erstelle einen neuen.")
                )
            }
        }
        .task {
            _ = await calendarService.requestAccess()
        }
        .errorAlert(errorHandler: errorHandler)
    }

    // MARK: - Extracted Views

    private var keynoteList: some View {
        List(selection: $selection) {
            if selectedCategory == .alleAuftritte || selectedCategory == .vereinbarteAuftritte {
                // Keine Gruppierung - nur nach Datum sortiert
                ForEach(filteredKeynotes) { keynote in
                    keynoteRow(for: keynote)
                        .tag(keynote.id)
                }
            } else {
                // Gruppierung nach Section
                ForEach(groupedKeynotes, id: \.section) { group in
                    Section(group.section.title) {
                        ForEach(group.keynotes) { keynote in
                            keynoteRow(for: keynote)
                                .tag(keynote.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func keynoteRow(for keynote: Keynote) -> some View {
        Button {
            selection = keynote.id
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
                selection = keynote.id
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }

            Button(role: .destructive) {
                deleteKeynote(keynote)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .listRowBackground(
            selection == keynote.id ? Color.accentColor.opacity(0.15) : Color.clear
        )
    }

    // MARK: - Actions

    private func createNewKeynote() {
        let keynote = Keynote()
        newKeynote = keynote
        selection = keynote.id
    }
    
    private func updateStatus(for keynote: Keynote, to status: KeynoteStatus) {
        withAnimation {
            keynote.status = status
        }
    }
    
    private func deleteKeynote(_ keynote: Keynote) {
        withAnimation {
            // Deselektieren wenn das Element gelöscht wird
            if selection == keynote.id {
                selection = nil
            }
            
            // Kalender-Event löschen, falls vorhanden
            if let eventID = keynote.calendarEventID {
                Task {
                    try? await calendarService.deleteEvent(eventID: eventID)
                }
            }
            modelContext.delete(keynote)
        }
    }
    
    private func exportPDF() {
        let pdfData = KeynotePDFGenerator.generatePDF(
            keynotes: keynotes.filter { !$0.inAbklaerung },
            title: "Auftrittsübersicht"
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Auftrittsübersicht.pdf")
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

#Preview {
    ContentView()
        .modelContainer(previewContainer())
}
