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
                .task {
                    runContactNameMigration()
                    runStatusMigration()
                }
        }
        .modelContainer(sharedModelContainer)
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
}


