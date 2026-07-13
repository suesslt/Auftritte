//
//  FahrtenReportTests.swift
//  AuftritteTests
//
//  Tests für den Report «Steuerabzüge Fahrten»: Filter, Quartals-Zuordnung,
//  Kostenberechnung und Totale.
//

import Testing
import Foundation
@testable import Auftritte

struct FahrtenReportTests {

    private func trip(_ name: String, date: String, km: Int?, status: KeynoteStatus = .completed) -> Keynote {
        Keynote(
            eventName: name,
            eventDate: ISO8601DateFormatter().date(from: date)!,
            status: status,
            distanceKm: km
        )
    }

    // MARK: - Filter

    @Test func relevantTrips_includes_completed_invoiced_closed() {
        let keynotes = [
            trip("A", date: "2025-02-01T10:00:00Z", km: 50, status: .completed),
            trip("B", date: "2025-03-01T10:00:00Z", km: 60, status: .invoiced),
            trip("C", date: "2025-04-01T10:00:00Z", km: 70, status: .closed)
        ]
        #expect(FahrtenPDFGenerator.relevantTrips(from: keynotes).count == 3)
    }

    @Test func relevantTrips_excludes_open_and_cancelled_and_missing_distance() {
        let keynotes = [
            trip("Offen", date: "2025-02-01T10:00:00Z", km: 50, status: .requested),
            trip("Abgesagt", date: "2025-03-01T10:00:00Z", km: 60, status: .cancelled),
            trip("Ohne Distanz", date: "2025-04-01T10:00:00Z", km: nil, status: .completed),
            trip("Distanz Null", date: "2025-05-01T10:00:00Z", km: 0, status: .completed)
        ]
        #expect(FahrtenPDFGenerator.relevantTrips(from: keynotes).isEmpty)
    }

    @Test func relevantTrips_sorts_chronologically() {
        let keynotes = [
            trip("Später", date: "2025-11-01T10:00:00Z", km: 50),
            trip("Früher", date: "2025-01-01T10:00:00Z", km: 60)
        ]
        let trips = FahrtenPDFGenerator.relevantTrips(from: keynotes)
        #expect(trips.map(\.eventName) == ["Früher", "Später"])
    }

    // MARK: - Quartals-Zuordnung

    @Test func yearAndQuarter_maps_months_correctly() {
        let f = ISO8601DateFormatter()
        #expect(FahrtenPDFGenerator.yearAndQuarter(of: f.date(from: "2025-01-15T10:00:00Z")!) == (2025, 1))
        #expect(FahrtenPDFGenerator.yearAndQuarter(of: f.date(from: "2025-03-15T10:00:00Z")!) == (2025, 1))
        #expect(FahrtenPDFGenerator.yearAndQuarter(of: f.date(from: "2025-04-15T10:00:00Z")!) == (2025, 2))
        #expect(FahrtenPDFGenerator.yearAndQuarter(of: f.date(from: "2025-07-15T10:00:00Z")!) == (2025, 3))
        #expect(FahrtenPDFGenerator.yearAndQuarter(of: f.date(from: "2025-12-15T10:00:00Z")!) == (2025, 4))
    }

    // MARK: - Kosten

    @Test func kosten_is_roundtrip_km_times_price() {
        // 2 × 85 km × 0.70 = 119.00
        #expect(FahrtenPDFGenerator.kosten(km: 85, preis: Decimal(string: "0.70")!) == Decimal(string: "119.00")!)
    }

    @Test func kosten_rounds_to_rappen() {
        // 2 × 33 km × 0.755 = 49.83
        #expect(FahrtenPDFGenerator.kosten(km: 33, preis: Decimal(string: "0.755")!) == Decimal(string: "49.83")!)
    }

    // MARK: - Zeilenmodell

    @Test func makeReportRows_empty_yields_notice() {
        let rows = FahrtenPDFGenerator.makeReportRows(trips: [], preis: 0.70)
        #expect(rows.count == 1)
        guard case .emptyNotice = rows[0] else {
            Issue.record("Erwartet .emptyNotice, erhalten: \(rows[0])")
            return
        }
    }

    @Test func makeReportRows_builds_quarter_and_year_totals() {
        let preis = Decimal(string: "0.70")!
        let trips = FahrtenPDFGenerator.relevantTrips(from: [
            trip("Q1a", date: "2024-02-01T10:00:00Z", km: 50),
            trip("Q1b", date: "2024-03-01T10:00:00Z", km: 30),
            trip("Q3", date: "2024-08-01T10:00:00Z", km: 100),
            trip("NextYear", date: "2025-01-10T10:00:00Z", km: 40)
        ])
        let rows = FahrtenPDFGenerator.makeReportRows(trips: trips, preis: preis)

        // Erwartet: [Q1 2024, trip, trip, Total Q1, Q3 2024, trip, Total Q3, Total 2024,
        //            Q1 2025, trip, Total Q1, Total 2025]
        #expect(rows.count == 12)

        var quarterTotals: [(String, Int, Decimal)] = []
        var yearTotals: [(Int, Int, Decimal)] = []
        for row in rows {
            if case .quarterTotal(let label, let km, let kosten) = row {
                quarterTotals.append((label, km, kosten))
            }
            if case .yearTotal(let year, let km, let kosten) = row {
                yearTotals.append((year, km, kosten))
            }
        }

        #expect(quarterTotals.count == 3)
        #expect(quarterTotals[0].0 == "Total Q1 2024")
        #expect(quarterTotals[0].1 == 80)
        #expect(quarterTotals[0].2 == Decimal(string: "112.00")!) // 2×80×0.70
        #expect(quarterTotals[1].1 == 100)
        #expect(quarterTotals[1].2 == Decimal(string: "140.00")!)
        #expect(quarterTotals[2].1 == 40)

        #expect(yearTotals.count == 2)
        #expect(yearTotals[0].0 == 2024)
        #expect(yearTotals[0].1 == 180)
        #expect(yearTotals[0].2 == Decimal(string: "252.00")!) // 112 + 140
        #expect(yearTotals[1].0 == 2025)
        #expect(yearTotals[1].1 == 40)
        #expect(yearTotals[1].2 == Decimal(string: "56.00")!)
    }

    // MARK: - PDF Smoke-Test

    @Test @MainActor func generatePDF_returns_nonempty_data() {
        let keynotes = [
            trip("A", date: "2025-02-01T10:00:00Z", km: 85),
            trip("B", date: "2025-06-01T10:00:00Z", km: 40)
        ]
        let data = FahrtenPDFGenerator.generatePDF(keynotes: keynotes, kilometerpreisCHF: 0.70)
        #expect(!data.isEmpty)
    }

    @Test @MainActor func generatePDF_empty_input_returns_nonempty_data() {
        let data = FahrtenPDFGenerator.generatePDF(keynotes: [], kilometerpreisCHF: 0.70)
        #expect(!data.isEmpty)
    }
}
