//
//  NewAuftrittSheet.swift
//  Auftritte
//
//  Kalender-first Neuanlage: Jeder neue Auftritt basiert auf einem Kalendereintrag.
//  Drei Pfade:
//  1. Bestehenden Kalendereintrag übernehmen (noch nicht verknüpfte Events).
//  2. Neuer Termin — die App erstellt sofort den Kalendereintrag.
//  3. «Datum noch nicht geklärt» — bewusste Ausnahme ohne Kalendereintrag.
//

import Score
import SwiftUI
import SwiftData
import EventKit
import ScoreUI

struct NewAuftrittSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var calendarService: CalendarService
    @Query private var keynotes: [Keynote]
    @StateObject private var errorHandler = ErrorHandler()

    /// Meldet den erstellten Auftritt zurück; `didCreateEvent` ist true, wenn die App
    /// den Kalendereintrag selbst angelegt hat (Pfad 2) — beim Abbrechen der Neuanlage
    /// muss er dann wieder entfernt werden.
    let onCreated: (_ keynote: Keynote, _ didCreateEvent: Bool) -> Void

    @State private var availableEvents: [ReconciliationEvent] = []
    @State private var showingNewTermin = false
    @State private var isCreating = false

    private var hasFullAccess: Bool {
        calendarService.authorizationStatus == .fullAccess
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingNewTermin = true
                    } label: {
                        Label("Neuer Termin", systemImage: "calendar.badge.plus")
                    }
                    .disabled(!hasFullAccess || calendarService.configuredCalendar == nil)

                    Button {
                        createInAbklaerung()
                    } label: {
                        Label("Datum noch nicht geklärt", systemImage: "questionmark.circle")
                    }
                } footer: {
                    Text("«Neuer Termin» erstellt sofort einen Kalendereintrag. Ohne geklärtes Datum bleibt der Auftritt vorerst ohne Kalendereintrag.")
                }

                kalenderSection
            }
            .navigationTitle("Neuer Auftritt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showingNewTermin) {
                NewTerminForm(isCreating: $isCreating, onCreate: createWithNewEvent)
            }
        }
        .errorAlert(errorHandler: errorHandler)
        .task { await loadEvents() }
    }

    // MARK: - Pfad 1: Aus Kalender übernehmen

    @ViewBuilder
    private var kalenderSection: some View {
        Section("Aus Kalender übernehmen") {
            if !hasFullAccess {
                Text("Kalenderzugriff verweigert. Bitte in den Systemeinstellungen erlauben.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if calendarService.configuredCalendar == nil {
                Text("Kein Kalender ausgewählt. Bitte wähle in den Einstellungen den Kalender für Auftritte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if availableEvents.isEmpty {
                Text("Keine offenen Kalendereinträge — alle kommenden Termine sind bereits mit Auftritten verknüpft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableEvents) { event in
                    Button {
                        adopt(event)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ReconciliationEngine.displayTitle(for: event))
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text(event.start, format: .dateTime.weekday(.abbreviated).day().month().year().hour().minute())
                                if let location = event.location, !location.isEmpty {
                                    Text("· \(location)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Kommende Events des Zielkalenders, die noch keinem Auftritt zugeordnet sind.
    private func loadEvents() async {
        guard hasFullAccess, calendarService.configuredCalendar != nil else { return }
        let now = Date.now
        let horizon = Calendar.home.date(byAdding: .year, value: ReconciliationEngine.horizonYears, to: now) ?? now
        let events = calendarService.fetchSyncEvents(from: now, to: horizon)
        availableEvents = ReconciliationEngine
            .reconcile(keynotes: keynotes, events: events, now: now)
            .onlyInCalendar
    }

    private func adopt(_ event: ReconciliationEvent) {
        let keynote = ReconciliationEngine.makeKeynote(from: event, status: .requested)
        modelContext.insert(keynote)
        try? modelContext.save()
        onCreated(keynote, false)
        dismiss()
    }

    // MARK: - Pfad 2: Neuer Termin

    private func createWithNewEvent(name: String, date: Date, duration: Double, location: String) {
        isCreating = true
        Task {
            defer { isCreating = false }
            let keynote = Keynote(
                eventName: name,
                eventDate: date,
                keynoteTitle: name,
                duration: duration,
                location: location,
                status: .requested
            )
            do {
                guard let eventID = try await calendarService.createSaveTheDate(for: keynote) else {
                    throw CalendarError.accessDenied
                }
                keynote.calendarEventID = eventID
                keynote.calendarLinkedAt = .now
                modelContext.insert(keynote)
                try modelContext.save()
                onCreated(keynote, true)
                dismiss()
            } catch {
                errorHandler.handle(error, title: "Termin konnte nicht erstellt werden")
            }
        }
    }

    // MARK: - Pfad 3: Datum noch nicht geklärt

    private func createInAbklaerung() {
        let keynote = Keynote(inAbklaerung: true)
        modelContext.insert(keynote)
        onCreated(keynote, false)
        dismiss()
    }
}

// MARK: - Minimal-Formular für Pfad 2

private struct NewTerminForm: View {
    @Binding var isCreating: Bool
    let onCreate: (_ name: String, _ date: Date, _ duration: Double, _ location: String) -> Void

    @State private var name = ""
    @State private var date = defaultStart()
    @State private var duration: Double = 60
    @State private var location = ""

    /// Nächste volle Stunde als Vorschlag.
    private static func defaultStart() -> Date {
        let calendar = Calendar.home
        let next = calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return calendar.date(bySetting: .minute, value: 0, of: next) ?? next
    }

    var body: some View {
        Form {
            Section("Termin") {
                TextField("Name des Anlasses", text: $name)
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                DatePicker("Zeit", selection: $date, displayedComponents: .hourAndMinute)
                HStack {
                    Text("Redezeit")
                    Spacer()
                    TextField("Minuten", value: $duration, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("Min.")
                }
                TextField("Ort", text: $location)
            }

            Section {
                Button {
                    onCreate(name, date, duration, location)
                } label: {
                    if isCreating {
                        HStack {
                            ProgressView()
                            Text("Wird erstellt…")
                        }
                    } else {
                        Label("Termin im Kalender eintragen", systemImage: "calendar.badge.plus")
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            } footer: {
                Text("Erstellt den Kalendereintrag und öffnet danach die Detailansicht des Auftritts.")
            }
        }
        .navigationTitle("Neuer Termin")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NewAuftrittSheet(onCreated: { _, _ in })
        .modelContainer(for: Keynote.self, inMemory: true)
        .environmentObject(CalendarService())
}
