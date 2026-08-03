//
//  FahrtenPDFGenerator.swift
//  Auftritte
//
//  Report «Steuerabzüge Fahrten»: tabellarische Liste aller gefahrenen Auftritte
//  pro Quartal mit Quartals- und Jahrestotalen, A4 Querformat.
//  Kosten = 2 × Distanz × Kilometerpreis (Hin- und Rückfahrt).
//

import Foundation
import UIKit

@MainActor
final class FahrtenPDFGenerator {

    // MARK: - Layout-Konstanten

    private static let pageWidth: CGFloat = 842   // A4 quer
    private static let pageHeight: CGFloat = 595
    private static let pageMargin: CGFloat = 30
    private static let headerHeight: CGFloat = 50
    private static let footerHeight: CGFloat = 20
    private static let columnHeaderHeight: CGFloat = 20

    private static var contentTop: CGFloat { pageMargin + headerHeight }
    private static var contentBottom: CGFloat { pageHeight - pageMargin - footerHeight }
    private static var contentWidth: CGFloat { pageWidth - 2 * pageMargin }

    // Spalten: (x, Breite, rechtsbündig)
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

    static func generatePDF(
        keynotes: [Keynote],
        kilometerpreisCHF: Decimal,
        generationDate: Date = Date()
    ) -> Data {
        let trips = relevantTrips(from: keynotes)
        let rows = makeReportRows(trips: trips, preis: kilometerpreisCHF)
        let pages = paginate(rows)
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let pdfData = NSMutableData()
        var mediaBox = pageRect

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        for (pageIndex, pageRows) in pages.enumerated() {
            pdfContext.beginPDFPage(nil)

            drawPageHeader(
                tripCount: trips.count,
                kilometerpreis: kilometerpreisCHF,
                generationDate: generationDate,
                pageRect: pageRect,
                context: pdfContext
            )
            drawColumnHeaders(pageRect: pageRect, context: pdfContext)

            var y = contentTop + columnHeaderHeight
            var tripIndex = 0
            for row in pageRows {
                drawRow(row, at: y, tripIndex: &tripIndex, preis: kilometerpreisCHF, pageRect: pageRect, context: pdfContext)
                y += row.height
            }

            drawFooter(pageNumber: pageIndex + 1, totalPages: pages.count, pageRect: pageRect, context: pdfContext)
            pdfContext.endPDFPage()
        }

        pdfContext.closePDF()
        return pdfData as Data
    }

    // MARK: - Pagination

    /// Teilt die Zeilen in Seiten auf. Ein Quartals-Header steht nie als letzte Zeile einer Seite.
    private static func paginate(_ rows: [ReportRow]) -> [[ReportRow]] {
        let capacity = contentBottom - contentTop - columnHeaderHeight
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

    // MARK: - Drawing: Header / Spaltenkopf / Footer

    private static func drawPageHeader(
        tripCount: Int,
        kilometerpreis: Decimal,
        generationDate: Date,
        pageRect: CGRect,
        context: CGContext
    ) {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let titleRect = CGRect(x: pageMargin, y: pageMargin, width: contentWidth * 0.6, height: 26)
        drawText("Steuerabzüge Fahrten", in: titleRect, pageRect: pageRect, attributes: titleAttrs, context: context)

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = .home
        let preisString = chfFormatter.string(from: kilometerpreis as NSDecimalNumber) ?? "CHF \(kilometerpreis)"
        let subtitle = "\(tripCount) Fahrten • Kilometerpreis \(preisString)/km • Erstellt am \(formatter.string(from: generationDate))"
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        let subtitleRect = CGRect(x: pageMargin, y: pageMargin + 28, width: contentWidth * 0.8, height: 16)
        drawText(subtitle, in: subtitleRect, pageRect: pageRect, attributes: subtitleAttrs, context: context)

        // Trennlinie unterhalb des Headers
        context.saveGState()
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(0.5)
        let lineY = pageHeight - (pageMargin + headerHeight - 4)
        context.move(to: CGPoint(x: pageMargin, y: lineY))
        context.addLine(to: CGPoint(x: pageMargin + contentWidth, y: lineY))
        context.strokePath()
        context.restoreGState()
    }

    private static func drawColumnHeaders(pageRect: CGRect, context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        let y = contentTop + 2
        drawText("Datum", in: CGRect(x: colDatum.x, y: y, width: colDatum.w, height: 13), pageRect: pageRect, attributes: attrs, context: context)
        drawText("Organisation", in: CGRect(x: colOrganisation.x, y: y, width: colOrganisation.w, height: 13), pageRect: pageRect, attributes: attrs, context: context)
        drawText("Titel", in: CGRect(x: colTitel.x, y: y, width: colTitel.w, height: 13), pageRect: pageRect, attributes: attrs, context: context)
        drawText("Ort", in: CGRect(x: colOrt.x, y: y, width: colOrt.w, height: 13), pageRect: pageRect, attributes: attrs, context: context)
        drawText("Kilometer", in: CGRect(x: colKilometer.x, y: y, width: colKilometer.w, height: 13), pageRect: pageRect, attributes: attrs, context: context, alignment: .right)
        drawText("Kosten (CHF)", in: CGRect(x: colKosten.x, y: y, width: colKosten.w, height: 13), pageRect: pageRect, attributes: attrs, context: context, alignment: .right)

        // Unterstreichung des Spaltenkopfs
        drawHorizontalLine(atY: y + 15, lineWidth: 0.5, color: UIColor.darkGray, context: context)
    }

    private static func drawFooter(pageNumber: Int, totalPages: Int, pageRect: CGRect, context: CGContext) {
        let footerText = "Seite \(pageNumber) von \(totalPages)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        let size = (footerText as NSString).size(withAttributes: attrs)
        let rect = CGRect(
            x: (pageWidth - size.width) / 2,
            y: pageHeight - pageMargin / 2 - size.height / 2,
            width: size.width,
            height: size.height
        )
        drawText(footerText, in: rect, pageRect: pageRect, attributes: attrs, context: context)
    }

    // MARK: - Drawing: Zeilen

    private static func drawRow(
        _ row: ReportRow,
        at y: CGFloat,
        tripIndex: inout Int,
        preis: Decimal,
        pageRect: CGRect,
        context: CGContext
    ) {
        switch row {
        case .quarterHeader(let label):
            // Graues Band über die volle Breite
            let bandRect = CGRect(x: pageMargin, y: y + 2, width: contentWidth, height: row.height - 4)
            context.saveGState()
            context.setFillColor(UIColor(white: 0.90, alpha: 1.0).cgColor)
            context.fill(flip(bandRect, in: pageRect))
            context.restoreGState()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            drawText(label, in: CGRect(x: colDatum.x + 4, y: y + 4, width: 200, height: 13), pageRect: pageRect, attributes: attrs, context: context)

        case .trip(let keynote):
            if tripIndex % 2 == 1 {
                let zebraRect = CGRect(x: pageMargin, y: y, width: contentWidth, height: row.height)
                context.saveGState()
                context.setFillColor(UIColor(white: 0.96, alpha: 1.0).cgColor)
                context.fill(flip(zebraRect, in: pageRect))
                context.restoreGState()
            }
            tripIndex += 1

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor.black
            ]
            let km = keynote.distanceKm ?? 0
            let cost = kosten(km: km, preis: preis)
            let textY = y + 2
            drawText(dateFormatter.string(from: keynote.eventDate), in: CGRect(x: colDatum.x, y: textY, width: colDatum.w, height: 12), pageRect: pageRect, attributes: attrs, context: context)
            drawText(keynote.clientOrganization, in: CGRect(x: colOrganisation.x, y: textY, width: colOrganisation.w, height: 12), pageRect: pageRect, attributes: attrs, context: context)
            drawText(keynote.keynoteTitle, in: CGRect(x: colTitel.x, y: textY, width: colTitel.w, height: 12), pageRect: pageRect, attributes: attrs, context: context)
            drawText(keynote.location, in: CGRect(x: colOrt.x, y: textY, width: colOrt.w, height: 12), pageRect: pageRect, attributes: attrs, context: context)
            drawText(String(km), in: CGRect(x: colKilometer.x, y: textY, width: colKilometer.w, height: 12), pageRect: pageRect, attributes: attrs, context: context, alignment: .right)
            drawText(formatKosten(cost), in: CGRect(x: colKosten.x, y: textY, width: colKosten.w, height: 12), pageRect: pageRect, attributes: attrs, context: context, alignment: .right)

        case .quarterTotal(let label, let km, let kosten):
            drawHorizontalLine(atY: y + 1, lineWidth: 0.5, color: UIColor.darkGray, context: context)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            drawTotalRow(label: label, km: km, kosten: kosten, attrs: attrs, atY: y + 4, pageRect: pageRect, context: context)

        case .yearTotal(let year, let km, let kosten):
            drawHorizontalLine(atY: y + 1, lineWidth: 1.2, color: UIColor.black, context: context)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            drawTotalRow(label: "Total \(String(year))", km: km, kosten: kosten, attrs: attrs, atY: y + 4, pageRect: pageRect, context: context)

        case .emptyNotice:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
            drawText("Keine Fahrten vorhanden", in: CGRect(x: colDatum.x, y: y + 2, width: contentWidth, height: 14), pageRect: pageRect, attributes: attrs, context: context)
        }
    }

    private static func drawTotalRow(
        label: String,
        km: Int,
        kosten: Decimal,
        attrs: [NSAttributedString.Key: Any],
        atY y: CGFloat,
        pageRect: CGRect,
        context: CGContext
    ) {
        drawText(label, in: CGRect(x: colOrt.x, y: y, width: colOrt.w, height: 13), pageRect: pageRect, attributes: attrs, context: context)
        drawText(String(km), in: CGRect(x: colKilometer.x, y: y, width: colKilometer.w, height: 13), pageRect: pageRect, attributes: attrs, context: context, alignment: .right)
        drawText(formatKosten(kosten), in: CGRect(x: colKosten.x, y: y, width: colKosten.w, height: 13), pageRect: pageRect, attributes: attrs, context: context, alignment: .right)
    }

    // MARK: - Formatierung

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "de_CH")
        f.timeZone = .home
        return f
    }()

    private static let chfFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CHF"
        f.locale = Locale(identifier: "de_CH")
        return f
    }()

    /// Kosten ohne Währungspräfix (die Spalte heisst bereits «Kosten (CHF)»).
    private static func formatKosten(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "de_CH")
        return f.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    // MARK: - Text-Hilfen

    private static func drawHorizontalLine(atY y: CGFloat, lineWidth: CGFloat, color: UIColor, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        let flippedY = pageHeight - y
        context.move(to: CGPoint(x: pageMargin, y: flippedY))
        context.addLine(to: CGPoint(x: pageMargin + contentWidth, y: flippedY))
        context.strokePath()
        context.restoreGState()
    }

    private static func flip(_ rect: CGRect, in pageRect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: pageRect.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        pageRect: CGRect,
        attributes: [NSAttributedString.Key: Any],
        context: CGContext,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail,
        alignment: NSTextAlignment = .left
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = lineBreakMode
        paragraphStyle.alignment = alignment
        var attrs = attributes
        attrs[.paragraphStyle] = paragraphStyle

        let nsString = text as NSString
        context.saveGState()
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        nsString.draw(in: rect, withAttributes: attrs)
        UIGraphicsPopContext()
        context.restoreGState()
    }
}
