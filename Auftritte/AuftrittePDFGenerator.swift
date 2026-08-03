//
//  KeynotePDFGenerator.swift
//  Auftritte
//
//  PDF-Export mit 2×2-Grid pro Seite (4 Einträge), A4 Querformat.
//  Nutzt die volle Seitenbreite — jede Zelle zeigt alle Auftritts-Informationen.
//

import Foundation
import UIKit
import SwiftUI

@MainActor
class KeynotePDFGenerator {

    // MARK: - Layout-Konstanten

    private static let pageWidth: CGFloat = 842   // A4 quer
    private static let pageHeight: CGFloat = 595
    private static let pageMargin: CGFloat = 30
    private static let headerHeight: CGFloat = 50   // Kopfzeile auf jeder Seite
    private static let footerHeight: CGFloat = 20
    private static let gridGap: CGFloat = 12
    private static let cellPadding: CGFloat = 10
    private static let cellsPerPage: Int = 4
    private static let cellsPerRow: Int = 2

    private static var contentTop: CGFloat { pageMargin + headerHeight }
    private static var contentBottom: CGFloat { pageHeight - pageMargin - footerHeight }
    private static var contentWidth: CGFloat { pageWidth - 2 * pageMargin }
    private static var contentHeight: CGFloat { contentBottom - contentTop }

    private static var cellWidth: CGFloat {
        (contentWidth - gridGap) / CGFloat(cellsPerRow)
    }
    private static var cellHeight: CGFloat {
        (contentHeight - gridGap) / CGFloat(cellsPerPage / cellsPerRow)
    }

    // MARK: - Public API

    static func generatePDF(
        keynotes: [Keynote],
        title: String = "Auftrittsübersicht",
        generationDate: Date = Date()
    ) -> Data {
        let sortedKeynotes = keynotes.sorted { $0.eventDate < $1.eventDate }
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let pdfData = NSMutableData()
        var mediaBox = pageRect

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let totalPages = max(1, Int(ceil(Double(sortedKeynotes.count) / Double(cellsPerPage))))

        for pageIndex in 0..<totalPages {
            pdfContext.beginPDFPage(nil)

            drawPageHeader(
                title: title,
                pageNumber: pageIndex + 1,
                totalPages: totalPages,
                totalKeynotes: sortedKeynotes.count,
                generationDate: generationDate,
                pageRect: pageRect,
                context: pdfContext
            )

            // Bis zu 4 Einträge dieser Seite
            let startIndex = pageIndex * cellsPerPage
            let endIndex = min(startIndex + cellsPerPage, sortedKeynotes.count)
            for (i, globalIndex) in (startIndex..<endIndex).enumerated() {
                let cellRect = cellRectFor(positionOnPage: i)
                drawKeynoteCell(
                    sortedKeynotes[globalIndex],
                    index: globalIndex + 1,
                    in: cellRect,
                    pageRect: pageRect,
                    context: pdfContext
                )
            }

            drawFooter(pageNumber: pageIndex + 1, totalPages: totalPages, pageRect: pageRect, context: pdfContext)
            pdfContext.endPDFPage()
        }

        pdfContext.closePDF()
        return pdfData as Data
    }

    // MARK: - Layout-Hilfen

    /// Liefert das Rechteck einer Zelle (0…3) im 2×2-Grid.
    private static func cellRectFor(positionOnPage i: Int) -> CGRect {
        let row = i / cellsPerRow
        let col = i % cellsPerRow
        let x = pageMargin + CGFloat(col) * (cellWidth + gridGap)
        let y = contentTop + CGFloat(row) * (cellHeight + gridGap)
        return CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
    }

    // MARK: - Drawing: Header / Footer

    private static func drawPageHeader(
        title: String,
        pageNumber: Int,
        totalPages: Int,
        totalKeynotes: Int,
        generationDate: Date,
        pageRect: CGRect,
        context: CGContext
    ) {
        // Titel links
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let titleRect = CGRect(x: pageMargin, y: pageMargin, width: contentWidth * 0.6, height: 26)
        drawText(title, in: titleRect, pageRect: pageRect, attributes: titleAttrs, context: context)

        // Untertitel
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = .home
        let subtitle = "\(totalKeynotes) Auftritte • Erstellt am \(formatter.string(from: generationDate))"
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        let subtitleRect = CGRect(x: pageMargin, y: pageMargin + 28, width: contentWidth * 0.6, height: 16)
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

    // MARK: - Drawing: Einzelne Zelle

    private static func drawKeynoteCell(
        _ keynote: Keynote,
        index: Int,
        in cellRect: CGRect,
        pageRect: CGRect,
        context: CGContext
    ) {
        // Hintergrund (abgerundetes Rechteck)
        let backgroundColor = index % 2 == 0
            ? UIColor(white: 0.96, alpha: 1.0)
            : UIColor.white
        context.saveGState()
        context.setFillColor(backgroundColor.cgColor)
        context.setStrokeColor(UIColor(white: 0.82, alpha: 1.0).cgColor)
        context.setLineWidth(0.5)
        let flippedBg = flip(cellRect, in: pageRect)
        let path = CGPath(roundedRect: flippedBg, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.drawPath(using: .fillStroke)
        context.restoreGState()

        // Status-Farbpunkt oben rechts
        let statusDotSize: CGFloat = 9
        let statusDotRect = CGRect(
            x: cellRect.maxX - cellPadding - statusDotSize,
            y: cellRect.minY + cellPadding + 3,
            width: statusDotSize,
            height: statusDotSize
        )
        let flippedDot = flip(statusDotRect, in: pageRect)
        context.saveGState()
        context.setFillColor(UIColor(keynote.status.color).cgColor)
        context.fillEllipse(in: flippedDot)
        context.restoreGState()

        // Text-Inhalte
        let contentRect = cellRect.insetBy(dx: cellPadding, dy: cellPadding)
        let textWidth = contentRect.width
        var y = contentRect.minY

        // Date-Formatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "de_DE")
        dateFormatter.timeZone = .home
        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        dayFormatter.locale = Locale(identifier: "de_DE")
        dayFormatter.timeZone = .home

        // Attribute
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        let regularAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.black
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor.black
        ]

        // 1. Event-Name (mit Index-Präfix)
        let nameWidth = textWidth - statusDotSize - 8
        let nameRect = CGRect(x: contentRect.minX, y: y, width: nameWidth, height: 18)
        drawText("\(index). \(keynote.eventName)", in: nameRect, pageRect: pageRect, attributes: headerAttrs, context: context, lineBreakMode: .byTruncatingTail)
        y += 19

        // 2. Datum & Status
        let dateString = keynote.inAbklaerung
            ? "Datum noch nicht geklärt"
            : dateFormatter.string(from: keynote.eventDate)
        let metaLine = "\(dateString)  •  \(keynote.status.rawValue)"
        drawLine(metaLine, at: &y, width: textWidth, x: contentRect.minX, attrs: metaAttrs, pageRect: pageRect, context: context, height: 13)

        // 3. Titel
        if !keynote.keynoteTitle.isEmpty {
            drawLabelValue("Titel:", value: keynote.keynoteTitle, at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, pageRect: pageRect, context: context)
        }

        // 4. Thema
        if !keynote.keynoteTheme.isEmpty {
            drawLabelValue("Thema:", value: keynote.keynoteTheme, at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, pageRect: pageRect, context: context)
        }

        // 5. Ort
        if !keynote.location.isEmpty {
            drawLabelValue("Ort:", value: keynote.location, at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, pageRect: pageRect, context: context)
        }

        // 6. Organisation
        if !keynote.clientOrganization.isEmpty {
            drawLabelValue("Organisation:", value: keynote.clientOrganization, at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, pageRect: pageRect, context: context)
        }

        // 7. Kontakt
        if keynote.contactHasData {
            var parts: [String] = [keynote.contactDisplayName]
            if !keynote.contactEmail.isEmpty { parts.append(keynote.contactEmail) }
            if !keynote.contactPhone.isEmpty { parts.append(keynote.contactPhone) }
            drawLabelValue("Kontakt:", value: parts.joined(separator: " • "), at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, pageRect: pageRect, context: context)
        }

        // 8. Zielpublikum + Anzahl Zuhörer (kombiniert wenn beides vorhanden)
        var audienceParts: [String] = []
        if !keynote.targetAudience.isEmpty { audienceParts.append(keynote.targetAudience) }
        if let n = keynote.attendeeCount { audienceParts.append("\(n) Personen") }
        if !audienceParts.isEmpty {
            drawLabelValue("Publikum:", value: audienceParts.joined(separator: " • "), at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, pageRect: pageRect, context: context)
        }

        // 9. Dauer • Honorar • Sprache
        let feeFormatter = NumberFormatter()
        feeFormatter.numberStyle = .currency
        feeFormatter.currencyCode = "CHF"
        feeFormatter.locale = Locale(identifier: "de_CH")
        let feeString = feeFormatter.string(from: keynote.agreedFee as NSDecimalNumber) ?? "CHF 0"
        var infoParts: [String] = [
            String(format: "%.0f Min.", keynote.duration),
            feeString
        ]
        if !keynote.language.isEmpty { infoParts.append(keynote.language) }
        drawLine(infoParts.joined(separator: "  •  "), at: &y, width: textWidth, x: contentRect.minX, attrs: metaAttrs, pageRect: pageRect, context: context, height: 13)

        // 10. Pendenz (Typ + Note + Erledigt-Status)
        let hasPendenz = !keynote.pendenzNote.isEmpty || keynote.pendenz != .none
        if hasPendenz {
            var pendenzText = "\(keynote.pendenz.rawValue)"
            if !keynote.pendenzNote.isEmpty {
                pendenzText += ": \(keynote.pendenzNote)"
            }
            pendenzText += keynote.pendenzErledigt ? "  ✓" : ""
            drawLabelValue("Pendenz:", value: pendenzText, at: &y, x: contentRect.minX, width: textWidth, labelAttrs: labelAttrs, valueAttrs: regularAttrs, pageRect: pageRect, context: context)
        }

        // 11. Angefragt am
        let requestText = "Angefragt am \(dayFormatter.string(from: keynote.requestDate))"
        drawLine(requestText, at: &y, width: textWidth, x: contentRect.minX, attrs: metaAttrs, pageRect: pageRect, context: context, height: 13)

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
                    pageRect: pageRect,
                    context: context,
                    height: min(remainingHeight, 40),
                    lineBreakMode: .byTruncatingTail
                )
            }
        }
    }

    // MARK: - Text-Hilfen

    private static func drawLine(
        _ text: String,
        at y: inout CGFloat,
        width: CGFloat,
        x: CGFloat,
        attrs: [NSAttributedString.Key: Any],
        pageRect: CGRect,
        context: CGContext,
        height: CGFloat = 13
    ) {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        drawText(text, in: rect, pageRect: pageRect, attributes: attrs, context: context, lineBreakMode: .byTruncatingTail)
        y += height + 1
    }

    private static func drawLabelValue(
        _ label: String,
        value: String,
        at y: inout CGFloat,
        x: CGFloat,
        width: CGFloat,
        labelAttrs: [NSAttributedString.Key: Any],
        valueAttrs: [NSAttributedString.Key: Any],
        pageRect: CGRect,
        context: CGContext,
        height: CGFloat = 13,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail
    ) {
        let labelSize = (label as NSString).size(withAttributes: labelAttrs)
        let labelW = labelSize.width + 4
        let labelRect = CGRect(x: x, y: y, width: labelW, height: height)
        drawText(label, in: labelRect, pageRect: pageRect, attributes: labelAttrs, context: context, lineBreakMode: .byTruncatingTail)
        let valueRect = CGRect(x: x + labelW, y: y, width: width - labelW, height: height)
        drawText(value, in: valueRect, pageRect: pageRect, attributes: valueAttrs, context: context, lineBreakMode: lineBreakMode)
        y += height + 1
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
        lineBreakMode: NSLineBreakMode = .byTruncatingTail
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = lineBreakMode
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
