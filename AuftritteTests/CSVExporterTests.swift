//
//  CSVExporterTests.swift
//  AuftritteTests
//

import Testing
import Foundation
@testable import Auftritte

struct CSVExporterTests {

    @Test func exporter_writes_all_headers() async throws {
        let csv = await KeynoteCSVExporter().buildCSV([])
        let firstLine = csv.split(separator: "\r\n").first.map(String.init) ?? ""

        for header in KeynoteCSVExporter.headers {
            #expect(firstLine.contains(header), "Header `\(header)` fehlt in CSV: \(firstLine)")
        }
        #expect(firstLine.contains("contactFirstName"))
        #expect(firstLine.contains("contactLastName"))
        #expect(firstLine.contains("pendenzNote"))
        #expect(firstLine.contains("pendenzErledigt"))
    }

    @Test func exporter_uses_crlf_line_endings() async throws {
        let keynote = Keynote(eventName: "Test", eventDate: Date())
        let csv = await KeynoteCSVExporter().buildCSV([keynote])
        #expect(csv.contains("\r\n"))
    }

    @Test func exporter_quotes_fields_with_commas() async throws {
        let keynote = Keynote(eventName: "Tagung, Zürich", eventDate: Date())
        let csv = await KeynoteCSVExporter().buildCSV([keynote])
        #expect(csv.contains("\"Tagung, Zürich\""))
    }

    @Test func exporter_escapes_double_quotes_rfc4180() async throws {
        let keynote = Keynote(eventName: "Test", eventDate: Date(), notes: "Mit \"Quotes\" drin")
        let csv = await KeynoteCSVExporter().buildCSV([keynote])
        // RFC 4180: "" inside a quoted field
        #expect(csv.contains("\"Mit \"\"Quotes\"\" drin\""))
    }

    @Test func exporter_quotes_fields_with_newlines() async throws {
        let keynote = Keynote(eventName: "Test", eventDate: Date(), notes: "Zeile1\nZeile2")
        let csv = await KeynoteCSVExporter().buildCSV([keynote])
        #expect(csv.contains("\"Zeile1\nZeile2\""))
    }

    @Test func exporter_formats_bool_as_true_false() async throws {
        let k1 = Keynote(eventName: "A", eventDate: Date(), inAbklaerung: true, pendenzErledigt: true)
        let k2 = Keynote(eventName: "B", eventDate: Date(), inAbklaerung: false, pendenzErledigt: false)
        let csv = await KeynoteCSVExporter().buildCSV([k1, k2])
        #expect(csv.contains("true"))
        #expect(csv.contains("false"))
    }

    @Test func exporter_attendeeCount_nil_yields_empty() async throws {
        let keynote = Keynote(eventName: "Test", eventDate: Date(), attendeeCount: nil)
        let csv = await KeynoteCSVExporter().buildCSV([keynote])
        // Letzte Spalten: attendeeCount + distanceKm → die Zeile endet mit zwei leeren Feldern
        let dataLine = csv.split(separator: "\r\n").last.map(String.init) ?? ""
        #expect(dataLine.hasSuffix(",,"))
    }

    @Test func exporter_distanceKm_nil_yields_empty() async throws {
        let keynote = Keynote(eventName: "Test", eventDate: Date(), distanceKm: nil)
        let csv = await KeynoteCSVExporter().buildCSV([keynote])
        // Letzte Spalte: distanceKm → die Zeile endet mit Komma + leerem Feld
        let dataLine = csv.split(separator: "\r\n").last.map(String.init) ?? ""
        #expect(dataLine.hasSuffix(","))
    }

    @Test func exporter_distanceKm_writes_value_as_last_column() async throws {
        let keynote = Keynote(eventName: "Test", eventDate: Date(), distanceKm: 87)
        let csv = await KeynoteCSVExporter().buildCSV([keynote])
        let dataLine = csv.split(separator: "\r\n").last.map(String.init) ?? ""
        #expect(dataLine.hasSuffix(",87"))
    }

    @Test func exporter_writes_firstname_and_lastname() async throws {
        let keynote = Keynote(
            eventName: "Test",
            eventDate: Date(),
            contactFirstName: "Hans-Peter",
            contactLastName: "von Müller"
        )
        let csv = await KeynoteCSVExporter().buildCSV([keynote])
        #expect(csv.contains("Hans-Peter"))
        #expect(csv.contains("von Müller"))
    }

    @Test func exporter_legacy_contactFullName_kombiniert() async throws {
        let keynote = Keynote(
            eventName: "Test",
            eventDate: Date(),
            contactFirstName: "Anna",
            contactLastName: "Beck"
        )
        let csv = await KeynoteCSVExporter().buildCSV([keynote])
        // combinedContactName erzeugt "Anna Beck" für die Legacy-Spalte
        #expect(csv.contains("Anna Beck"))
    }
}
