//
//  FahrtenPDFGenerator.swift
//  Auftritte
//
//  Report «Steuerabzüge Fahrten»: tabellarische Liste aller gefahrenen Auftritte
//  pro Quartal mit Quartals- und Jahrestotalen, A4 Querformat.
//  Kosten = 2 × Distanz × Kilometerpreis (Hin- und Rückfahrt).
//
//  Seit der ScoreUI-Adoption (score v2.5.0, 2026-08-06) liefert
//  `ReportPDFRenderer` die Infrastruktur (PDF-Lifecycle, Rect-Text mit
//  Truncation/Ausrichtung, Linien, Report-Kopf/-Fuss); hier verbleiben
//  Fachlogik, Zeilenmodell und Tabellen-Layout.
//

import Score
import ScoreUI
import Foundation
import UIKit

nonisolated final class FahrtenPDFGenerator: ReportPDFRenderer {

    // MARK: - Layout-Konstanten

    private static let columnHeaderHeight: CGFloat = 20

    // Spalten: (x, Breite)
    private static let colDatum: (x: CGFloat, w: CGFloat) = (30, 70)
    private static let colOrganisation: (x: CGFloat, w: CGFloat) = (108, 190)
    private static let colTitel: (x: CGFloat, w: CGFloat) = (306, 220)
    private static let colOrt: (x: CGFloat, w: CGFloat) = (534, 132)
    private static let colKilometer: (x: CGFloat, w: CGFloat) = (674, 60)
    private static let colKosten: (x: CGFloat, w: CGFloat) = (742, 70)

    // MARK: - Zeilenmodell

    enum ReportRow {
        case quarterHeader(String)                                  // "Q1 2025"
        case trip(Keynote)
        case quarterTotal(label: String, km: Int, kosten: Decimal)  // "Total Q1 2025"
        case yearTotal(year: Int, km: Int, kosten: Decimal)
        case emptyNotice

        var height: CGFloat {
            switch self {
            case .quarterHeader: return 20
            case .trip: return 16
            case .quarterTotal: return 18
            case .yearTotal: return 20
            case .emptyNotice: return 16
            }
        }
    }

    // MARK: - Fachlogik (testbar)

    /// Nur tatsächlich gefahrene Auftritte: durchgeführt (inkl. Folge-Status) mit erfasster Distanz.
    nonisolated static func relevantTrips(from keynotes: [Keynote]) -> [Keynote] {
        keynotes
            .filter { [.completed, .invoiced, .closed].contains($0.status) && ($0.distanceKm ?? 0) > 0 }
            .sorted { $0.eventDate < $1.eventDate }
    }

    /// Quartal 1–4 aus dem Monat, ohne Foundation-`.quarter` (unzuverlässig).
    nonisolated static func yearAndQuarter(of date: Date) -> (year: Int, quarter: Int) {
        let comps = Calendar.home.dateComponents([.year, .month], from: date)
        return (comps.year ?? 0, ((comps.month ?? 1) - 1) / 3 + 1)
    }

    /// Kosten = 2 × km × Preis, auf Rappen gerundet.
    nonisolated static func kosten(km: Int, preis: Decimal) -> Decimal {
        var raw = Decimal(2 * km) * preis
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return rounded
    }

    /// Baut das flache Zeilenmodell: pro Quartal Header + Fahrten + Total, pro Jahr ein Jahrestotal.
    /// Totale summieren die gerundeten Zeilenwerte, damit sie zu den gedruckten Zeilen passen.
    nonisolated static func makeReportRows(trips: [Keynote], preis: Decimal) -> [ReportRow] {
        guard !trips.isEmpty else { return [.emptyNotice] }

        var rows: [ReportRow] = []
        var quarterKm = 0, quarterKosten = Decimal(0)
        var yearKm = 0, yearKosten = Decimal(0)
        var current: (year: Int, quarter: Int)?

        func closeQuarter() {
            guard let c = current else { return }
            rows.append(.quarterTotal(label: "Total Q\(c.quarter) \(String(c.year))", km: quarterKm, kosten: quarterKosten))
            quarterKm = 0
            quarterKosten = 0
        }

        func closeYear() {
            guard let c = current else { return }
            rows.append(.yearTotal(year: c.year, km: yearKm, kosten: yearKosten))
            yearKm = 0
            yearKosten = 0
        }

        for trip in trips {
            let key = yearAndQuarter(of: trip.eventDate)
            if key.year != current?.year || key.quarter != current?.quarter {
                closeQuarter()
                if let c = current, c.year != key.year {
                    closeYear()
                }
                current = key
                rows.append(.quarterHeader("Q\(key.quarter) \(String(key.year))"))
            }
            rows.append(.trip(trip))
            let km = trip.distanceKm ?? 0
            let cost = kosten(km: km, preis: preis)
            quarterKm += km
            quarterKosten += cost
            yearKm += km
            yearKosten += cost
        }
        closeQuarter()
        closeYear()
        return rows
    }

    // MARK: - Public API

    @MainActor
    static func generatePDF(
        keynotes: [Keynote],
        kilometerpreisCHF: Decimal,
        generationDate: Date = Date()
    ) -> Data {
        FahrtenPDFGenerator().render(
            keynotes: keynotes,
            kilometerpreisCHF: kilometerpreisCHF,
            generationDate: generationDate
        )
    }

    @MainActor
    private func render(keynotes: [Keynote], kilometerpreisCHF: Decimal, generationDate: Date) -> Data {
        let trips = Self.relevantTrips(from: keynotes)
        let rows = Self.makeReportRows(trips: trips, preis: kilometerpreisCHF)
        let pages = paginate(rows)

        guard let (context, pdfData) = beginPDF() else { return Data() }

        let preisString = Money.of(.chf, kilometerpreisCHF).formatted
        let erstelltAm = Self.headerDateFormatter.string(from: generationDate)
        let subtitle = "\(trips.count) Fahrten • Kilometerpreis \(preisString)/km • Erstellt am \(erstelltAm)"

        for (pageIndex, pageRows) in pages.enumerated() {
            if pageIndex > 0 { newPage(context: context) }

            drawReportHeader(context: context, title: "Steuerabzüge Fahrten", subtitle: subtitle)
            drawColumnHeaders(context: context)

            var y = contentTop + Self.columnHeaderHeight
            var tripIndex = 0
            for row in pageRows {
                drawRow(row, at: y, tripIndex: &tripIndex, preis: kilometerpreisCHF, context: context)
                y += row.height
            }

            drawReportFooter(context: context, pageNumber: pageIndex + 1, totalPages: pages.count)
        }

        return endPDF(context: context, pdfData: pdfData)
    }

    // MARK: - Pagination

    /// Teilt die Zeilen in Seiten auf. Ein Quartals-Header steht nie als letzte Zeile einer Seite.
    private func paginate(_ rows: [ReportRow]) -> [[ReportRow]] {
        let capacity = contentBottom - contentTop - Self.columnHeaderHeight
        var pages: [[ReportRow]] = []
        var currentPage: [ReportRow] = []
        var usedHeight: CGFloat = 0

        for row in rows {
            if usedHeight + row.height > capacity {
                // Verwaisten Quartals-Header auf die nächste Seite mitnehmen
                if case .quarterHeader = currentPage.last {
                    let header = currentPage.removeLast()
                    pages.append(currentPage)
                    currentPage = [header, row]
                    usedHeight = header.height + row.height
                } else {
                    pages.append(currentPage)
                    currentPage = [row]
                    usedHeight = row.height
                }
            } else {
                currentPage.append(row)
                usedHeight += row.height
            }
        }
        if !currentPage.isEmpty {
            pages.append(currentPage)
        }
        return pages.isEmpty ? [[]] : pages
    }

    // MARK: - Drawing: Spaltenkopf

    @MainActor
    private func drawColumnHeaders(context: CGContext) {
        let attrs = attributes(size: 9, weight: .semibold)
        let y = contentTop + 2
        drawText(context: context, "Datum", in: CGRect(x: Self.colDatum.x, y: y, width: Self.colDatum.w, height: 13), attributes: attrs)
        drawText(context: context, "Organisation", in: CGRect(x: Self.colOrganisation.x, y: y, width: Self.colOrganisation.w, height: 13), attributes: attrs)
        drawText(context: context, "Titel", in: CGRect(x: Self.colTitel.x, y: y, width: Self.colTitel.w, height: 13), attributes: attrs)
        drawText(context: context, "Ort", in: CGRect(x: Self.colOrt.x, y: y, width: Self.colOrt.w, height: 13), attributes: attrs)
        drawText(context: context, "Kilometer", in: CGRect(x: Self.colKilometer.x, y: y, width: Self.colKilometer.w, height: 13), attributes: attrs, alignment: .right)
        drawText(context: context, "Kosten (CHF)", in: CGRect(x: Self.colKosten.x, y: y, width: Self.colKosten.w, height: 13), attributes: attrs, alignment: .right)

        // Unterstreichung des Spaltenkopfs
        drawHRule(context: context, y: y + 15, from: marginLeft, to: marginLeft + contentWidth,
                  lineWidth: 0.5, color: UIColor.darkGray.cgColor)
    }

    // MARK: - Drawing: Zeilen

    @MainActor
    private func drawRow(
        _ row: ReportRow,
        at y: CGFloat,
        tripIndex: inout Int,
        preis: Decimal,
        context: CGContext
    ) {
        switch row {
        case .quarterHeader(let label):
            // Graues Band über die volle Breite
            fillRect(context: context, x: marginLeft, y: y + 2,
                     width: contentWidth, height: row.height - 4,
                     color: CGColor(gray: 0.90, alpha: 1.0))
            drawText(context: context, label,
                     in: CGRect(x: Self.colDatum.x + 4, y: y + 4, width: 200, height: 13),
                     attributes: attributes(size: 10, weight: .semibold))

        case .trip(let keynote):
            if tripIndex % 2 == 1 {
                fillRect(context: context, x: marginLeft, y: y,
                         width: contentWidth, height: row.height,
                         color: CGColor(gray: 0.96, alpha: 1.0))
            }
            tripIndex += 1

            let attrs = attributes(size: 9)
            let km = keynote.distanceKm ?? 0
            let cost = Self.kosten(km: km, preis: preis)
            let textY = y + 2
            drawText(context: context, Self.dateFormatter.string(from: keynote.eventDate), in: CGRect(x: Self.colDatum.x, y: textY, width: Self.colDatum.w, height: 12), attributes: attrs)
            drawText(context: context, keynote.clientOrganization, in: CGRect(x: Self.colOrganisation.x, y: textY, width: Self.colOrganisation.w, height: 12), attributes: attrs)
            drawText(context: context, keynote.keynoteTitle, in: CGRect(x: Self.colTitel.x, y: textY, width: Self.colTitel.w, height: 12), attributes: attrs)
            drawText(context: context, keynote.location, in: CGRect(x: Self.colOrt.x, y: textY, width: Self.colOrt.w, height: 12), attributes: attrs)
            drawText(context: context, String(km), in: CGRect(x: Self.colKilometer.x, y: textY, width: Self.colKilometer.w, height: 12), attributes: attrs, alignment: .right)
            drawText(context: context, Self.formatKosten(cost), in: CGRect(x: Self.colKosten.x, y: textY, width: Self.colKosten.w, height: 12), attributes: attrs, alignment: .right)

        case .quarterTotal(let label, let km, let kosten):
            drawHRule(context: context, y: y + 1, from: marginLeft, to: marginLeft + contentWidth,
                      lineWidth: 0.5, color: UIColor.darkGray.cgColor)
            drawTotalRow(label: label, km: km, kosten: kosten,
                         attrs: attributes(size: 9, weight: .semibold), atY: y + 4, context: context)

        case .yearTotal(let year, let km, let kosten):
            drawHRule(context: context, y: y + 1, from: marginLeft, to: marginLeft + contentWidth,
                      lineWidth: 1.2, color: UIColor.black.cgColor)
            drawTotalRow(label: "Total \(String(year))", km: km, kosten: kosten,
                         attrs: attributes(size: 10, weight: .bold), atY: y + 4, context: context)

        case .emptyNotice:
            drawText(context: context, "Keine Fahrten vorhanden",
                     in: CGRect(x: Self.colDatum.x, y: y + 2, width: contentWidth, height: 14),
                     attributes: attributes(size: 11, color: .darkGray))
        }
    }

    @MainActor
    private func drawTotalRow(
        label: String,
        km: Int,
        kosten: Decimal,
        attrs: [NSAttributedString.Key: Any],
        atY y: CGFloat,
        context: CGContext
    ) {
        drawText(context: context, label, in: CGRect(x: Self.colOrt.x, y: y, width: Self.colOrt.w, height: 13), attributes: attrs)
        drawText(context: context, String(km), in: CGRect(x: Self.colKilometer.x, y: y, width: Self.colKilometer.w, height: 13), attributes: attrs, alignment: .right)
        drawText(context: context, Self.formatKosten(kosten), in: CGRect(x: Self.colKosten.x, y: y, width: Self.colKosten.w, height: 13), attributes: attrs, alignment: .right)
    }

    // MARK: - Formatierung

    @MainActor private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = .home
        return f
    }()

    @MainActor private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "de_CH")
        f.timeZone = .home
        return f
    }()

    /// Kosten ohne Währungspräfix (die Spalte heisst bereits «Kosten (CHF)»).
    private static func formatKosten(_ value: Decimal) -> String {
        Money.of(.chf, value).formattedAmount(locale: Locale(identifier: "de_CH"))
    }
}
