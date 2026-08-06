//
//  PDFGeneratorSmokeTests.swift
//  AuftritteTests
//
//  Smoke-Tests nach der ScoreUI-ReportPDFRenderer-Adoption (score v2.5.0):
//  Die Generatoren liefern parsebare PDFs mit der erwarteten Seitenzahl.
//

import Foundation
import PDFKit
import Testing
@testable import Auftritte

struct PDFGeneratorSmokeTests {

    private func keynote(_ name: String, date: String, km: Int? = nil,
                         status: KeynoteStatus = .completed) -> Keynote {
        Keynote(
            eventName: name,
            eventDate: ISO8601DateFormatter().date(from: date)!,
            keynoteTitle: "Titel \(name)",
            clientOrganization: "Organisation \(name)",
            location: "Zürich",
            status: status,
            notes: "Notiz \(name)",
            distanceKm: km
        )
    }

    @MainActor
    @Test func keynotePDF_five_entries_yield_two_pages() {
        let keynotes = (1...5).map { keynote("K\($0)", date: "2025-0\($0)-01T10:00:00Z") }
        let data = KeynotePDFGenerator.generatePDF(keynotes: keynotes,
                                                   generationDate: Date(timeIntervalSince1970: 1_750_000_000))
        let document = try! #require(PDFDocument(data: data))
        #expect(document.pageCount == 2)   // 4 Zellen pro Seite → 5 Einträge = 2 Seiten
        // A4 quer
        let bounds = document.page(at: 0)!.bounds(for: .mediaBox)
        #expect(bounds.width > bounds.height)
    }

    @MainActor
    @Test func keynotePDF_empty_input_yields_one_page() {
        let data = KeynotePDFGenerator.generatePDF(keynotes: [])
        let document = try! #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
    }

    @MainActor
    @Test func fahrtenPDF_renders_trips_and_totals() {
        let keynotes = [
            keynote("A", date: "2025-02-01T10:00:00Z", km: 50),
            keynote("B", date: "2025-05-01T10:00:00Z", km: 60),
        ]
        let data = FahrtenPDFGenerator.generatePDF(keynotes: keynotes, kilometerpreisCHF: Decimal(string: "0.70")!)
        let document = try! #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        let text = document.page(at: 0)?.string ?? ""
        #expect(text.contains("Steuerabzüge Fahrten"))
        #expect(text.contains("Total 2025"))
    }
}
