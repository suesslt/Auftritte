//
//  ContentView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Keynote.eventDate, order: .forward) private var keynotes: [Keynote]
    
    @State private var searchText = ""
    @State private var newKeynote: Keynote?
    @State private var selection: Keynote.ID?
    @State private var statusFilter: KeynoteStatus?
    @State private var showingStats = false
    @State private var showingPDFExport = false
    @State private var showingCSVImport = false
    @StateObject private var calendarService = CalendarService()
    @StateObject private var errorHandler = ErrorHandler()

    var filteredKeynotes: [Keynote] {
        var filtered = keynotes
        
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
                keynote.location.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filteredKeynotes) { keynote in
                    NavigationLink(value: keynote.id) {
                        KeynoteRowView(keynote: keynote)
                    }
                    .listRowBackground(
                        selection == keynote.id ? Color.gray.opacity(0.3) : Color.clear
                    )
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
                }
            }
            .navigationTitle("Auftritte")
            .searchable(text: $searchText, prompt: "Suchen...")
            .toolbar {
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
                            Label("PDF exportieren", systemImage: "doc.fill")
                        }
                        
                        Divider()
                        
                        Button(action: { showingCSVImport = true }) {
                            Label("CSV importieren", systemImage: "square.and.arrow.down.on.square")
                        }
                    } label: {
                        Label("Mehr", systemImage: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: createNewKeynote) {
                        Label("Neuer Auftritt", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: Keynote.ID.self) { _ in
                // Wird durch detail: Closure abgedeckt
                EmptyView()
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
            .sheet(isPresented: $showingPDFExport) {
                PDFExportView(keynotes: keynotes)
            }
            .sheet(isPresented: $showingCSVImport) {
                CSVImportView()
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
        showingPDFExport = true
    }
}

// MARK: - Keynote Row View
struct KeynoteRowView: View {
    let keynote: Keynote

    var body: some View {
        KeynoteListItemView(
            keynote: keynote,
            contactName: keynote.contactHasData ? keynote.contactFullName : nil
        )
        .foregroundColor(.primary)
    }
}

#Preview {
    ContentView()
        .modelContainer(previewContainer())
}
