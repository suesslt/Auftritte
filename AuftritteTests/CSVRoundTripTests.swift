//
//  CSVRoundTripTests.swift
//  AuftritteTests
//
//  Verifiziert, dass Export → Import alle Felder eines Keynote-Datensatzes
//  verlustfrei erhält — inkl. Spezialzeichen, Mehrteiler-Namen und Migration.
//

import Testing
import Foundation
@testable import Auftritte

struct CSVRoundTripTests {

    @Test func roundtrip_preserves_all_fields() async throws {
        let original = Keynote(
            eventName: "Tech Conference 2026",
            eventDate: ISO8601DateFormatter().date(from: "2026-09-15T10:30:00Z")!,
            keynoteTitle: "KI und Recht",
            keynoteTheme: "Compliance",
            duration: 45,
            clientOrganization: "Acme AG",
            contactFirstName: "Hans-Peter",
            contactLastName: "von Müller",
            contactFullName: "",
            contactEmail: "hans@example.com",
            contactPhone: "+41 79 123 45 67",
            targetAudience: "Juristen",
            location: "Zürich, Park Hyatt",
            status: .invoiced,
            requestDate: ISO8601DateFormatter().date(from: "2026-01-10T08:00:00Z")!,
            notes: "Erste Zeile, mit Komma\nZweite Zeile mit \"Quotes\"",
            language: "Deutsch",
            inAbklaerung: false,
            pendenz: .speaker,
            pendenzNote: "Folien vorbereiten",
            pendenzErledigt: false,
            attendeeCount: 120
        )
        original.agreedFeeInCents = 850_000

        let csv = await KeynoteCSVExporter().buildCSV([original])
        let result = try await KeynoteCSVImporter().parse(csv)

        #expect(result.rows.count == 1)
        let reimported = try #require(result.rows[0].keynote)

        #expect(reimported.eventName == original.eventName)
        #expect(reimported.eventDate == original.eventDate)
        #expect(reimported.keynoteTitle == original.keynoteTitle)
        #expect(reimported.keynoteTheme == original.keynoteTheme)
        #expect(reimported.duration == original.duration)
        #expect(reimported.clientOrganization == original.clientOrganization)
        #expect(reimported.contactFirstName == "Hans-Peter")
        #expect(reimported.contactLastName == "von Müller")
        #expect(reimported.contactEmail == original.contactEmail)
        #expect(reimported.contactPhone == original.contactPhone)
        #expect(reimported.agreedFeeInCents == 850_000)
        #expect(reimported.targetAudience == original.targetAudience)
        #expect(reimported.location == original.location)
        #expect(reimported.status == .invoiced)
        #expect(reimported.requestDate == original.requestDate)
        #expect(reimported.notes == original.notes)
        #expect(reimported.language == original.language)
        #expect(reimported.inAbklaerung == false)
        #expect(reimported.pendenz == .speaker)
        #expect(reimported.pendenzNote == "Folien vorbereiten")
        #expect(reimported.pendenzErledigt == false)
        #expect(reimported.attendeeCount == 120)
    }

    @Test func roundtrip_preserves_multipart_lastname() async throws {
        // Heuristik aus contactFullName allein würde hier scheitern:
        // "Hans-Peter von Müller" → splitContactName ergäbe ("Hans-Peter", "von Müller") — OK
        // aber "Hans-Peter de la Cruz Müller" → ("Hans-Peter", "de la Cruz Müller") — Ok
        // Test verifiziert, dass die expliziten Spalten genutzt werden statt Heuristik.
        let original = Keynote(
            eventName: "Test",
            eventDate: Date(),
            contactFirstName: "Maria-José",
            contactLastName: "de la Cruz"
        )

        let csv = await KeynoteCSVExporter().buildCSV([original])
        let result = try await KeynoteCSVImporter().parse(csv)
        let reimported = try #require(result.rows[0].keynote)

        #expect(reimported.contactFirstName == "Maria-José")
        #expect(reimported.contactLastName == "de la Cruz")
    }

    @Test func roundtrip_migrates_legacy_status_csv() async throws {
        // Manuell konstruierte CSV mit altem statusRaw — simuliert Import einer
        // CSV-Datei, die mit einer früheren App-Version exportiert wurde.
        let csv = """
        eventName,eventDate,statusRaw\r
        AltesEvent,2026-09-15T10:30:00Z,Durchgeführt und in Rechnung gestellt\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.status == .completed)
    }

    @Test func roundtrip_status_completed_stays_completed() async throws {
        let original = Keynote(eventName: "Test", eventDate: Date(), status: .completed)
        let csv = await KeynoteCSVExporter().buildCSV([original])
        let result = try await KeynoteCSVImporter().parse(csv)
        let reimported = try #require(result.rows[0].keynote)
        #expect(reimported.status == .completed)
    }

    @Test func roundtrip_status_invoiced_stays_invoiced() async throws {
        let original = Keynote(eventName: "Test", eventDate: Date(), status: .invoiced)
        let csv = await KeynoteCSVExporter().buildCSV([original])
        let result = try await KeynoteCSVImporter().parse(csv)
        let reimported = try #require(result.rows[0].keynote)
        #expect(reimported.status == .invoiced)
    }
}
