//
//  CSVImporterTests.swift
//  AuftritteTests
//

import Testing
import Foundation
@testable import Auftritte

struct CSVImporterTests {

    @Test func importer_rejects_missing_eventName() async throws {
        let csv = """
        eventName,eventDate\r
        ,2026-09-15T10:00:00Z\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        #expect(result.rows.count == 1)
        let row = result.rows[0]
        #expect(row.keynote == nil)
        #expect(row.error != nil)
    }

    @Test func importer_rejects_invalid_date() async throws {
        let csv = """
        eventName,eventDate\r
        Test,nichtEinDatum\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        #expect(result.rows[0].keynote == nil)
        #expect(result.rows[0].error?.contains("Datum") == true)
    }

    @Test func importer_prefers_firstname_lastname_over_fullname() async throws {
        let csv = """
        eventName,eventDate,contactFirstName,contactLastName,contactFullName\r
        Test,2026-09-15T10:00:00Z,Hans-Peter,von Müller,Falsch Fallback\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.contactFirstName == "Hans-Peter")
        #expect(keynote.contactLastName == "von Müller")
    }

    @Test func importer_falls_back_to_fullname_split() async throws {
        let csv = """
        eventName,eventDate,contactFullName\r
        Test,2026-09-15T10:00:00Z,Max Mustermann\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.contactFirstName == "Max")
        #expect(keynote.contactLastName == "Mustermann")
    }

    @Test func importer_migrates_legacy_status_completedInvoiced() async throws {
        let csv = """
        eventName,eventDate,statusRaw\r
        Test,2026-09-15T10:00:00Z,Durchgeführt und in Rechnung gestellt\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.status == .completed)
    }

    @Test func importer_migrates_legacy_status_feedbackRequested() async throws {
        let csv = """
        eventName,eventDate,statusRaw\r
        Test,2026-09-15T10:00:00Z,Feedback angefragt\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.status == .closed)
    }

    @Test func importer_handles_escaped_double_quotes() async throws {
        let csv = """
        eventName,eventDate,notes\r
        Test,2026-09-15T10:00:00Z,"Mit ""Quotes"" drin"\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.notes == "Mit \"Quotes\" drin")
    }

    @Test func importer_handles_multiline_quoted_field() async throws {
        let csv = "eventName,eventDate,notes\r\nTest,2026-09-15T10:00:00Z,\"Zeile1\nZeile2\"\r\n"
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.notes == "Zeile1\nZeile2")
    }

    @Test func importer_parses_all_new_fields() async throws {
        let csv = """
        eventName,eventDate,pendenzRaw,pendenzNote,pendenzErledigt,inAbklaerung,distanceKm\r
        Test,2026-09-15T10:00:00Z,Speaker,Folien vorbereiten,true,false,87\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.pendenz == .speaker)
        #expect(keynote.pendenzNote == "Folien vorbereiten")
        #expect(keynote.pendenzErledigt == true)
        #expect(keynote.inAbklaerung == false)
        #expect(keynote.distanceKm == 87)
    }

    @Test func importer_empty_distanceKm_yields_nil() async throws {
        let csv = """
        eventName,eventDate,distanceKm\r
        Test,2026-09-15T10:00:00Z,\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.distanceKm == nil)
    }

    @Test func mappedStatusRaw_passes_through_known_values() {
        #expect(KeynoteCSVImporter.mappedStatusRaw("Angefragt") == "Angefragt")
        #expect(KeynoteCSVImporter.mappedStatusRaw("Abgebrochen") == "Abgebrochen")
        #expect(KeynoteCSVImporter.mappedStatusRaw("") == "")
    }

    @Test func importer_migrates_legacy_status_paid() async throws {
        let csv = """
        eventName,eventDate,statusRaw\r
        Test,2026-09-15T10:00:00Z,Bezahlt\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.status == .closed)
    }

    @Test func importer_migrates_legacy_status_cancelled() async throws {
        let csv = """
        eventName,eventDate,statusRaw\r
        Test,2026-09-15T10:00:00Z,Abgesagt\r
        """
        let result = try await KeynoteCSVImporter().parse(csv)
        let keynote = try #require(result.rows[0].keynote)
        #expect(keynote.status == .cancelled)
    }
}
