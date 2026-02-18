//
//  SampleData.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import Foundation
import SwiftData

/// Sample Data für Previews und Testing
extension Keynote {
    static let sampleKeynotes: [Keynote] = [
        Keynote(
            eventName: "Tech Conference 2026",
            eventDate: Date().addingTimeInterval(60 * 60 * 24 * 30), // In 30 Tagen
            keynoteTitle: "Die Zukunft der Künstlichen Intelligenz",
            keynoteTheme: "KI und Machine Learning",
            duration: 45,
            clientOrganization: "Tech Corp AG",
            agreedFee: 5000,
            targetAudience: "Führungskräfte und IT-Entscheider",
            location: "Zürich, Switzerland",
            status: .dateConfirmedFeeOffered,
            requestDate: Date().addingTimeInterval(-60 * 60 * 24 * 10),
            language: "Deutsch"
        ),
        Keynote(
            eventName: "Leadership Summit 2026",
            eventDate: Date().addingTimeInterval(60 * 60 * 24 * 60), // In 60 Tagen
            keynoteTitle: "Agile Leadership in der digitalen Transformation",
            keynoteTheme: "Leadership und Change Management",
            duration: 60,
            clientOrganization: "Global Leaders Inc.",
            agreedFee: 7500,
            targetAudience: "C-Level Executives",
            location: "Genf, Switzerland",
            status: .feeConfirmed,
            requestDate: Date().addingTimeInterval(-60 * 60 * 24 * 20),
            language: "Englisch"
        ),
        Keynote(
            eventName: "Innovation Day",
            eventDate: Date().addingTimeInterval(-60 * 60 * 24 * 30), // Vor 30 Tagen
            keynoteTitle: "Innovation als Treiber des Wachstums",
            keynoteTheme: "Innovation Management",
            duration: 50,
            clientOrganization: "Innovate GmbH",
            agreedFee: 4500,
            targetAudience: "Produktmanager und Entwickler",
            location: "Basel, Switzerland",
            status: .paid,
            requestDate: Date().addingTimeInterval(-60 * 60 * 24 * 90),
            language: "Deutsch"
        ),
        Keynote(
            eventName: "Digital Marketing Forum",
            eventDate: Date().addingTimeInterval(60 * 60 * 24 * 15), // In 15 Tagen
            keynoteTitle: "Die Macht der Daten im Marketing",
            keynoteTheme: "Data-Driven Marketing",
            duration: 40,
            clientOrganization: "Marketing Masters AG",
            agreedFee: 3500,
            targetAudience: "Marketing Professionals",
            location: "Bern, Switzerland",
            status: .contractSigned,
            requestDate: Date().addingTimeInterval(-60 * 60 * 24 * 5),
            language: "Deutsch"
        ),
        Keynote(
            eventName: "Startup Accelerator Event",
            eventDate: Date().addingTimeInterval(60 * 60 * 24 * 90), // In 90 Tagen
            keynoteTitle: "Von der Idee zum erfolgreichen Startup",
            keynoteTheme: "Entrepreneurship",
            duration: 30,
            clientOrganization: "Swiss Startup Hub",
            agreedFee: 2500,
            targetAudience: "Gründer und Investoren",
            location: "Lausanne, Switzerland",
            status: .requested,
            requestDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
            notes: "Anfrage per E-Mail von Max Mustermann erhalten. Noch Details zum genauen Zeitpunkt klären.",
            language: "Französisch"
        ),
        Keynote(
            eventName: "Healthcare Innovation Congress",
            eventDate: Date().addingTimeInterval(-60 * 60 * 24 * 60), // Vor 60 Tagen
            keynoteTitle: "Digitale Transformation im Gesundheitswesen",
            keynoteTheme: "Digital Health",
            duration: 55,
            clientOrganization: "HealthTech AG",
            agreedFee: 6000,
            targetAudience: "Ärzte und Klinikmanagement",
            location: "Luzern, Switzerland",
            status: .closed,
            requestDate: Date().addingTimeInterval(-60 * 60 * 24 * 120),
            language: "Deutsch"
        ),
        Keynote(
            eventName: "Sustainability Summit",
            eventDate: Date().addingTimeInterval(60 * 60 * 24 * 45), // In 45 Tagen
            keynoteTitle: "Nachhaltige Geschäftsmodelle der Zukunft",
            keynoteTheme: "Nachhaltigkeit und ESG",
            duration: 45,
            clientOrganization: "GreenFuture Foundation",
            agreedFee: 4000,
            targetAudience: "CSR Manager und Nachhaltigkeitsexperten",
            location: "St. Gallen, Switzerland",
            status: .contentAgreed,
            requestDate: Date().addingTimeInterval(-60 * 60 * 24 * 15),
            language: "Deutsch & Englisch"
        ),
        Keynote(
            eventName: "Banking Transformation Forum",
            eventDate: Date().addingTimeInterval(-60 * 60 * 24 * 15), // Vor 15 Tagen
            keynoteTitle: "Die Bank der Zukunft: Digital, aber menschlich",
            keynoteTheme: "Digital Banking",
            duration: 50,
            clientOrganization: "Swiss Banking Association",
            agreedFee: 8000,
            targetAudience: "Bank-Executives und Fintech-Experten",
            location: "Zürich, Switzerland",
            status: .completedInvoiced,
            requestDate: Date().addingTimeInterval(-60 * 60 * 24 * 75),
            language: "Englisch"
        )
    ]
    
    /// Fügt Sample-Daten in einen ModelContainer ein
    @MainActor
    static func insertSampleData(into modelContainer: ModelContainer) {
        let context = modelContainer.mainContext
        
        for keynote in sampleKeynotes {
            context.insert(keynote)
        }
        
        try? context.save()
    }
}

/// Preview Container mit Sample Data
@MainActor
func previewContainer() -> ModelContainer {
    let schema = Schema([Keynote.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    
    Keynote.insertSampleData(into: container)
    
    return container
}
