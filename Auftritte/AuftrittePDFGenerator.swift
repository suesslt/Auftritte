//
//  KeynotePDFGenerator.swift
//  Auftritte
//
//  PDF-Export mit 2×2-Grid pro Seite (4 Einträge), A4 Querformat.
//  Nutzt die volle Seitenbreite — jede Zelle zeigt alle Auftritts-Informationen.
//
//  Seit der ScoreUI-Adoption (score v2.5.0, 2026-08-06) liefert
//  `ReportPDFRenderer` die Infrastruktur (PDF-Lifecycle, Rect-Text mit
//  Truncation, Formen, Report-Kopf/-Fuss); hier verbleibt das Grid-Layout.
//

import Score
import ScoreUI
import Foundation
import UIKit
import SwiftUI

nonisolated final class KeynotePDFGenerator: ReportPDFRenderer {

    // MARK: - Grid-Konstanten

    private static let gridGap: CGFloat = 12
    private static let cellPadding: CGFloat = 10
    private static let cellsPerPage: Int = 4
    private static let cellsPerRow: Int = 2

    private var contentHeight: CGFloat { contentBottom - contentTop }
    private var cellWidth: CGFloat {
        (contentWidth - Self.gridGap) / CGFloat(Self.cellsPerRow)
    }
    private var cellHeight: CGFloat {
        (contentHeight - Self.gridGap) / CGFloat(Self.cellsPerPage / Self.cellsPerRow)
    }

    // MARK: - Public API

    @MainActor
    static func generatePDF(
        keynotes: [Keynote],
        title: String = "Auftrittsübersicht",
        generationDate: Date = Date()
    ) -> Data {
        KeynotePDFGenerator().render(keynotes: keynotes, title: title, generationDate: generationDate)
    }

    @MainActor
    private func render(keynotes: [Keynote], title: String, generationDate: Date) -> Data {
        let sortedKeynotes = keynotes.sorted { $0.eventDate < $1.eventDate }

        guard let (context, pdfData) = beginPDF() else { return Data() }

        let totalPages = max(1, Int(ceil(Double(sortedKeynotes.count) / Double(Self.cellsPerPage))))
        let subtitleDate = Self.headerDateFormatter.string(from: generationDate)
        let subtitle = "\(sortedKeynotes.count) Auftritte • Erstellt am \(subtitleDate)"

        for pageIndex in 0..<totalPages {
            if pageIndex > 0 { newPage(context: context) }

            drawReportHeader(context: context, title: title, subtitle: subtitle)

            // Bis zu 4 Einträge dieser Seite
            let startIndex = pageIndex * Self.cellsPerPage
            let endIndex = min(startIndex + Self.cellsPerPage, sortedKeynotes.count)
            for (i, globalIndex) in (startIndex..<endIndex).enumerated() {
                drawKeynoteCell(
                    sortedKeynotes[globalIndex],
                    index: globalIndex + 1,
                    in: cellRectFor(positionOnPage: i),
                    context: context
                )
            }

            drawReportFooter(context: context, pageNumber: pageIndex + 1, totalPages: totalPages)
        }

        return endPDF(context: context, pdfData: pdfData)
    }

    // MARK: - Layout-Hilfen

    /// Liefert das Rechteck einer Zelle (0…3) im 2×2-Grid.
    private func cellRectFor(positionOnPage i: Int) -> CGRect {
        let row = i / Self.cellsPerRow
        let col = i % Self.cellsPerRow
        let x = marginLeft + CGFloat(col) * (cellWidth + Self.gridGap)
        let y = contentTop + CGFloat(row) * (cellHeight + Self.gridGap)
        return CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
    }

    // MARK: - Drawing: Einzelne Zelle

    @MainActor
    private func drawKeynoteCell(
        _ keynote: Keynote,
        index: Int,
        in cellRect: CGRect,
        context: CGContext
    ) {
        // Hintergrund (abgerundetes Rechteck)
        let backgroundColor = index % 2 == 0
            ? UIColor(white: 0.96, alpha: 1.0)
            : UIColor.white
        fillRoundedRect(
            context: context,
            rect: cellRect,
            cornerRadius: 6,
            fillColor: backgroundColor.cgColor,
            strokeColor: UIColor(white: 0.82, alpha: 1.0).cgColor,
            lineWidth: 0.5
        )

        // Status-Farbpunkt oben rechts
        let statusDotSize: CGFloat = 9
        let statusDotRect = CGRect(
            x: cellRect.maxX - Self.cellPadding - statusDotSize,
            y: cellRect.minY + Self.cellPadding + 3,
            width: statusDotSize,
            height: statusDotSize
        )
        fillEllipse(context: context, rect: statusDotRect, color: UIColor(keynote.status.color).cgColor)

        // Text-Inhalte
        let contentRect = cellRect.insetBy(dx: Self.cellPadding, dy: Self.cellPadding)
        let textWidth = contentRect.width
        var y = contentRect.minY

        // Attribute
        let headerAttrs = attributes(size: 13, weight: .semibold)
        let metaAttrs = attributes(size: 10, color: .darkGray)
        let regularAttrs = attributes(size: 10)
        let labelAttrs = attributes(size: 10, weight: .medium)

        // 1. Event-Name (mit Index-Präfix)
        let nameWidth = textWidth - statusDotSize - 8
        drawText(context: context, "\(index). \(keynote.eventName)",
                 in: CGRect(x: contentRect.minX, y: y, width: nameWidth, height: 18),
                 attributes: headerAttrs)
        y += 19

        // 2. Datum & Status
        let dateString = keynote.inAbklaerung
            ? "Datum noch nicht geklärt"
            : Self.cellDateFormatter.string(from: keynote.eventDate)
        let metaLine = "\(dateString)  •  \(keynote.status.rawValue)"
        drawLine(metaLine, at: &y, width: textWidth, x: contentRect.minX, attrs: metaAttrs, context: context)

        // 3. Titel
        if !keynote.keynoteTitle.isEmpty {
            drawLabelValue("Titel:", value: keynote.keynoteTitle, at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, context: context)
        }

        // 4. Thema
        if !keynote.keynoteTheme.isEmpty {
            drawLabelValue("Thema:", value: keynote.keynoteTheme, at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, context: context)
        }

        // 5. Ort
        if !keynote.location.isEmpty {
            drawLabelValue("Ort:", value: keynote.location, at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, context: context)
        }

        // 6. Organisation
        if !keynote.clientOrganization.isEmpty {
            drawLabelValue("Organisation:", value: keynote.clientOrganization, at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, context: context)
        }

        // 7. Kontakt
        if keynote.contactHasData {
            var parts: [String] = [keynote.contactDisplayName]
            if !keynote.contactEmail.isEmpty { parts.append(keynote.contactEmail) }
            if !keynote.contactPhone.isEmpty { parts.append(keynote.contactPhone) }
            drawLabelValue("Kontakt:", value: parts.joined(separator: " • "), at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, context: context)
        }

        // 8. Zielpublikum + Anzahl Zuhörer (kombiniert wenn beides vorhanden)
        var audienceParts: [String] = []
        if !keynote.targetAudience.isEmpty { audienceParts.append(keynote.targetAudience) }
        if let n = keynote.attendeeCount { audienceParts.append("\(n) Personen") }
        if !audienceParts.isEmpty {
            drawLabelValue("Publikum:", value: audienceParts.joined(separator: " • "), at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, context: context)
        }

        // 9. Dauer • Honorar • Sprache
        var infoParts: [String] = [
            String(format: "%.0f Min.", keynote.duration),
            keynote.agreedFeeMoney.formatted
        ]
        if !keynote.language.isEmpty { infoParts.append(keynote.language) }
        drawLine(infoParts.joined(separator: "  •  "), at: &y, width: textWidth, x: contentRect.minX, attrs: metaAttrs, context: context)

        // 10. Pendenz (Typ + Note + Erledigt-Status)
        let hasPendenz = !keynote.pendenzNote.isEmpty || keynote.pendenz != .none
        if hasPendenz {
            var pendenzText = "\(keynote.pendenz.rawValue)"
            if !keynote.pendenzNote.isEmpty {
                pendenzText += ": \(keynote.pendenzNote)"
            }
            pendenzText += keynote.pendenzErledigt ? "  ✓" : ""
            drawLabelValue("Pendenz:", value: pendenzText, at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, context: context)
        }

        // 11. Angefragt am
        let requestText = "Angefragt am \(Self.dayFormatter.string(from: keynote.requestDate))"
        drawLine(requestText, at: &y, width: textWidth, x: contentRect.minX, attrs: metaAttrs, context: context)

        // 12. Notizen — auf den verbleibenden Raum begrenzen
        if !keynote.notes.isEmpty {
            let remainingHeight = max(0, contentRect.maxY - y - 2)
            if remainingHeight >= 13 {
                drawLabelValue(
                    "Notizen:",
                    value: keynote.notes,
                    at: &y,
                    x: contentRect.minX,
                    width: textWidth,
                    labelAttrs: labelAttrs,
                    valueAttrs: regularAttrs,
                    context: context,
                    height: min(remainingHeight, 40),
                    lineBreakMode: .byTruncatingTail
                )
            }
        }
    }

    // MARK: - Text-Hilfen

    private func drawLine(
        _ text: String,
        at y: inout CGFloat,
        width: CGFloat,
        x: CGFloat,
        attrs: [NSAttributedString.Key: Any],
        context: CGContext,
        height: CGFloat = 13
    ) {
        drawText(context: context, text, in: CGRect(x: x, y: y, width: width, height: height), attributes: attrs)
        y += height + 1
    }

    @MainActor
    private func drawLabelValue(
        _ label: String,
        value: String,
        at y: inout CGFloat,
        x: CGFloat,
        width: CGFloat,
        labelAttrs: [NSAttributedString.Key: Any],
        valueAttrs: [NSAttributedString.Key: Any],
        context: CGContext,
        height: CGFloat = 13,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail
    ) {
        let labelSize = (label as NSString).size(withAttributes: labelAttrs)
        let labelW = labelSize.width + 4
        drawText(context: context, label,
                 in: CGRect(x: x, y: y, width: labelW, height: height), attributes: labelAttrs)
        drawText(context: context, value,
                 in: CGRect(x: x + labelW, y: y, width: width - labelW, height: height),
                 attributes: valueAttrs, lineBreakMode: lineBreakMode)
        y += height + 1
    }

    // MARK: - Formatter

    @MainActor private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = .home
        return f
    }()

    @MainActor private static let cellDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = .home
        return f
    }()

    @MainActor private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = .home
        return f
    }()
}
