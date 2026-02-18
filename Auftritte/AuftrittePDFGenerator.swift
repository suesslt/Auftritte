//
//  KeynotePDFGenerator.swift
//  Auftritte
//
//  Created by Thomas Süssli on 10.02.2026.
//

import Foundation
import UIKit
import SwiftUI

/// Service-Klasse zur Generierung von PDF-Dokumenten aus Keynote-Listen
@MainActor
class KeynotePDFGenerator {
    
    /// Generiert ein PDF-Dokument mit einer Liste aller Keynotes
    /// - Parameters:
    ///   - keynotes: Array von Keynotes (wird nach Datum sortiert)
    ///   - title: Titel des Dokuments (z.B. "Auftrittsübersicht 2026")
    ///   - generationDate: Datum der Erstellung (Standard: aktuelles Datum)
    /// - Returns: PDF-Daten als Data-Objekt
    static func generatePDF(
        keynotes: [Keynote],
        title: String = "Auftrittsübersicht",
        generationDate: Date = Date()
    ) -> Data {
        // Keynotes chronologisch sortieren
        let sortedKeynotes = keynotes.sorted { $0.eventDate < $1.eventDate }
        
        // PDF-Format konfigurieren (A4 Querformat)
        let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 Querformat
        
        let pdfData = NSMutableData()
        var mediaBox = pageRect
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        
        var yPosition: CGFloat = 60
        let margin: CGFloat = 40
        let pageWidth = pageRect.width - (margin * 2)
        var currentPage = 1
        
        // Erste Seite beginnen
        pdfContext.beginPDFPage(nil)
        
        // Titel zeichnen
        yPosition = drawTitle(title, at: yPosition, pageRect: pageRect, pageWidth: pageWidth, margin: margin, context: pdfContext)
        
        // Erstellungsdatum zeichnen
        yPosition = drawGenerationDate(generationDate, at: yPosition, pageRect: pageRect, pageWidth: pageWidth, margin: margin, context: pdfContext)
        
        // Trennlinie
        yPosition = drawSeparator(at: yPosition, pageRect: pageRect, pageWidth: pageWidth, margin: margin, context: pdfContext)
        
        // Zusammenfassung
        yPosition = drawSummary(count: sortedKeynotes.count, at: yPosition, pageRect: pageRect, pageWidth: pageWidth, margin: margin, context: pdfContext)
        
        yPosition += 20
        
        // Alle Keynotes durchlaufen
        for (index, keynote) in sortedKeynotes.enumerated() {
            // Neue Seite beginnen, wenn nicht genug Platz
            if yPosition > pageRect.height - 250 {
                drawFooter(pageNumber: currentPage, pageRect: pageRect, margin: margin, context: pdfContext)
                pdfContext.endPDFPage()
                pdfContext.beginPDFPage(nil)
                currentPage += 1
                yPosition = 60
            }
            
            yPosition = drawKeynote(
                keynote,
                index: index + 1,
                at: yPosition,
                pageRect: pageRect,
                pageWidth: pageWidth,
                margin: margin,
                context: pdfContext
            )
            
            yPosition += 25
        }
        
        // Fußzeile für die letzte Seite
        drawFooter(pageNumber: currentPage, pageRect: pageRect, margin: margin, context: pdfContext)
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        
        return pdfData as Data
    }
    
    // MARK: - Drawing Functions
    
    /// Converts a PDF coordinate (origin bottom-left) to a flipped coordinate (origin top-left)
    private static func flip(_ rect: CGRect, in pageRect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: pageRect.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
    
    private static func drawText(_ text: String, in rect: CGRect, pageRect: CGRect, attributes: [NSAttributedString.Key: Any], context: CGContext) {
        let flipped = flip(rect, in: pageRect)
        let nsString = text as NSString

        UIGraphicsPushContext(context)
        nsString.draw(in: flipped, withAttributes: attributes)
        UIGraphicsPopContext()
    }
    
    private static func drawTitle(_ title: String, at yPosition: CGFloat, pageRect: CGRect, pageWidth: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        
        let rect = CGRect(x: margin, y: yPosition, width: pageWidth, height: 40)
        drawText(title, in: rect, pageRect: pageRect, attributes: titleAttributes, context: context)
        
        return yPosition + 40
    }
    
    private static func drawGenerationDate(_ date: Date, at yPosition: CGFloat, pageRect: CGRect, pageWidth: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "de_DE")
        
        let dateString = "Erstellt am: \(dateFormatter.string(from: date))"
        
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        
        let rect = CGRect(x: margin, y: yPosition, width: pageWidth, height: 20)
        drawText(dateString, in: rect, pageRect: pageRect, attributes: dateAttributes, context: context)
        
        return yPosition + 25
    }
    
    private static func drawSeparator(at yPosition: CGFloat, pageRect: CGRect, pageWidth: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        context.saveGState()
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(1)
        
        let flippedY = pageRect.height - yPosition
        context.move(to: CGPoint(x: margin, y: flippedY))
        context.addLine(to: CGPoint(x: margin + pageWidth, y: flippedY))
        context.strokePath()
        
        context.restoreGState()
        
        return yPosition + 20
    }
    
    private static func drawSummary(count: Int, at yPosition: CGFloat, pageRect: CGRect, pageWidth: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        let summaryText = "Anzahl Auftritte: \(count)"
        
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor.black
        ]
        
        let rect = CGRect(x: margin, y: yPosition, width: pageWidth, height: 20)
        drawText(summaryText, in: rect, pageRect: pageRect, attributes: summaryAttributes, context: context)
        
        return yPosition + 25
    }
    
    private static func drawKeynote(
        _ keynote: Keynote,
        index: Int,
        at yPosition: CGFloat,
        pageRect: CGRect,
        pageWidth: CGFloat,
        margin: CGFloat,
        context: CGContext
    ) -> CGFloat {
        var currentY = yPosition
        let startY = currentY
        let contentMargin: CGFloat = 10
        
        // Formatierung vorbereiten
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "de_DE")
        
        let requestDateFormatter = DateFormatter()
        requestDateFormatter.dateStyle = .medium
        requestDateFormatter.locale = Locale(identifier: "de_DE")
        
        // Standard-Attribute definieren
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        
        let regularAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.black
        ]
        
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        
        // Collect all lines to draw so we only compute once
        struct TextLine {
            let text: String
            let y: CGFloat
            let attributes: [NSAttributedString.Key: Any]
            let height: CGFloat
        }
        var lines: [TextLine] = []
        
        // Event-Name
        lines.append(TextLine(text: keynote.eventName, y: currentY, attributes: headerAttributes, height: 20))
        currentY += 22
        
        // Datum und Status
        let dateString = dateFormatter.string(from: keynote.eventDate)
        let statusText = "\(dateString) • Status: \(keynote.status.rawValue)"
        lines.append(TextLine(text: statusText, y: currentY, attributes: secondaryAttributes, height: 18))
        currentY += 18
        
        // Keynote-Titel
        if !keynote.keynoteTitle.isEmpty {
            lines.append(TextLine(text: "Titel: \(keynote.keynoteTitle)", y: currentY, attributes: regularAttributes, height: 16))
            currentY += 16
        }
        
        // Thema
        if !keynote.keynoteTheme.isEmpty {
            lines.append(TextLine(text: "Thema: \(keynote.keynoteTheme)", y: currentY, attributes: regularAttributes, height: 16))
            currentY += 16
        }
        
        // Ort
        if !keynote.location.isEmpty {
            lines.append(TextLine(text: "Ort: \(keynote.location)", y: currentY, attributes: regularAttributes, height: 16))
            currentY += 16
        }
        
        // Organisation
        if !keynote.clientOrganization.isEmpty {
            lines.append(TextLine(text: "Organisation: \(keynote.clientOrganization)", y: currentY, attributes: regularAttributes, height: 16))
            currentY += 16
        }
        
        // Primärer Kontakt
        if let contact = keynote.primaryContact, contact.hasData {
            var contactText = "Kontakt: \(contact.displayName)"
            if !contact.email.isEmpty { contactText += " • \(contact.email)" }
            if !contact.phone.isEmpty { contactText += " • \(contact.phone)" }
            lines.append(TextLine(text: contactText, y: currentY, attributes: regularAttributes, height: 16))
            currentY += 16
        }
        
        // Zielpublikum
        if !keynote.targetAudience.isEmpty {
            lines.append(TextLine(text: "Zielpublikum: \(keynote.targetAudience)", y: currentY, attributes: regularAttributes, height: 16))
            currentY += 16
        }
        
        // Sprache
        if !keynote.language.isEmpty {
            lines.append(TextLine(text: "Sprache: \(keynote.language)", y: currentY, attributes: regularAttributes, height: 16))
            currentY += 16
        }
        
        // Dauer und Honorar
        let durationText = String(format: "Dauer: %.0f Min.", keynote.duration)
        let feeFormatter = NumberFormatter()
        feeFormatter.numberStyle = .currency
        feeFormatter.currencyCode = "CHF"
        let feeString = feeFormatter.string(from: keynote.agreedFee as NSDecimalNumber) ?? "CHF 0.00"
        let infoText = "\(durationText) • Honorar: \(feeString)"
        lines.append(TextLine(text: infoText, y: currentY, attributes: secondaryAttributes, height: 16))
        currentY += 16
        
        // Anfragedatum
        let requestDateString = requestDateFormatter.string(from: keynote.requestDate)
        let requestText = "Angefragt am: \(requestDateString)"
        lines.append(TextLine(text: requestText, y: currentY, attributes: secondaryAttributes, height: 16))
        currentY += 16
        
        // Notizen (falls vorhanden)
        if !keynote.notes.isEmpty {
            lines.append(TextLine(text: "Notizen: \(keynote.notes)", y: currentY, attributes: secondaryAttributes, height: 40))
            currentY += 42
        }
        
        // Hintergrund zeichnen
        let totalHeight = currentY - startY + 10
        let backgroundRect = CGRect(x: margin, y: startY - 5, width: pageWidth, height: totalHeight)
        let backgroundColor = index % 2 == 0
            ? UIColor(white: 0.95, alpha: 1.0)
            : UIColor.white
        
        context.saveGState()
        context.setFillColor(backgroundColor.cgColor)
        
        let flippedBg = flip(backgroundRect, in: pageRect)
        let path = CGPath(roundedRect: flippedBg, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
        
        // Alle Texte über dem Hintergrund zeichnen
        for line in lines {
            let rect = CGRect(x: margin + contentMargin, y: line.y, width: pageWidth - 20, height: line.height)
            drawText(line.text, in: rect, pageRect: pageRect, attributes: line.attributes, context: context)
        }
        
        return currentY
    }
    
    private static func drawFooter(pageNumber: Int, pageRect: CGRect, margin: CGFloat, context: CGContext) {
        let footerText = "Seite \(pageNumber)"
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        
        let nsString = footerText as NSString
        let size = nsString.size(withAttributes: footerAttributes)
        let footerY = pageRect.height - margin / 2
        let footerRect = CGRect(
            x: (pageRect.width - size.width) / 2,
            y: footerY,
            width: size.width,
            height: size.height
        )
        
        drawText(footerText, in: footerRect, pageRect: pageRect, attributes: footerAttributes, context: context)
    }
}
