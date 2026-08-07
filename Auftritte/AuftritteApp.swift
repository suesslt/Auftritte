//
//  KeynotesApp.swift
//  Keynotes
//
//  Created by Thomas Süssli on 08.02.2026.
//

import Score
import SwiftUI
import SwiftData

@main
struct KeynotesApp: App {
    /// Eine geteilte EventKit-Anbindung für die ganze App — nötig, damit der
    /// Auto-Abgleich und die Views denselben Store und Berechtigungsstatus sehen.
    @StateObject private var calendarService = CalendarService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Keynote.self,
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Datumseingabe und SwiftUI-Datumsanzeige fix in der Heimatzeitzone,
                // damit Termine auf Reisen nicht verschoben erscheinen.
                .environment(\.timeZone, .home)
                .environmentObject(calendarService)
                .task {
                    runContactNameMigration()
                    runStatusMigration()
                    runCalendarLinkStampMigration()
                }
        }
        .modelContainer(sharedModelContainer)
        // Zusätzlich auf Scene-Ebene injizieren: Environment-Objects erreichen
        // navigationDestination-/Sheet-Inhalte nicht auf allen Plattformen
        // zuverlässig, wenn sie nur auf der Root-View gesetzt sind.
        .environmentObject(calendarService)
    }

    /// Splittet das Legacy-Feld `contactFullName` einmalig in `contactFirstName` / `contactLastName`.
    /// Idempotent — bereits migrierte Datensätze werden übersprungen.
    private func runContactNameMigration() {
        let context = sharedModelContainer.mainContext
        guard let keynotes = try? context.fetch(FetchDescriptor<Keynote>()) else { return }
        var didMigrate = false
        for keynote in keynotes {
            let beforeFirst = keynote.contactFirstName
            let beforeLast = keynote.contactLastName
            keynote.migrateLegacyContactName()
            if keynote.contactFirstName != beforeFirst || keynote.contactLastName != beforeLast {
                didMigrate = true
            }
        }
        if didMigrate {
            try? context.save()
        }
    }

    /// Migriert obsolete Status-Werte:
    /// - "Durchgeführt und in Rechnung gestellt" → "Durchgeführt"
    /// - "Feedback angefragt" → "Abgeschlossen"
    /// - "Bezahlt" → "Abgeschlossen"
    /// - "Abgesagt" → "Abgebrochen"
    /// Idempotent — wirkt nur auf Datensätze mit alten Werten.
    private func runStatusMigration() {
        let mapping: [String: KeynoteStatus] = [
            "Durchgeführt und in Rechnung gestellt": .completed,
            "Feedback angefragt": .closed,
            "Bezahlt": .closed,
            "Abgesagt": .cancelled
        ]
        let context = sharedModelContainer.mainContext
        guard let keynotes = try? context.fetch(FetchDescriptor<Keynote>()) else { return }
        var didMigrate = false
        for keynote in keynotes {
            if let newStatus = mapping[keynote.statusRaw] {
                keynote.statusRaw = newStatus.rawValue
                didMigrate = true
            }
        }
        if didMigrate {
            try? context.save()
        }
    }

    /// Stempelt bestehende Kalender-Verknüpfungen mit `calendarLinkedAt = .now`.
    /// Gibt Bestandsdaten nach dem App-Update eine frische Grace-Period, damit der
    /// erste automatische Kalender-Abgleich nie Auftritte massenweise abbricht.
    /// Idempotent — wirkt nur auf verknüpfte Datensätze ohne Stempel.
    private func runCalendarLinkStampMigration() {
        let context = sharedModelContainer.mainContext
        guard let keynotes = try? context.fetch(FetchDescriptor<Keynote>()) else { return }
        var didMigrate = false
        for keynote in keynotes where keynote.calendarEventID != nil && keynote.calendarLinkedAt == nil {
            keynote.calendarLinkedAt = .now
            didMigrate = true
        }
        if didMigrate {
            try? context.save()
        }
    }
}


