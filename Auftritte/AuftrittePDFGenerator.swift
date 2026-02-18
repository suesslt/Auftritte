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
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let data = renderer.pdfData { context in
            var yPosition: CGFloat = 60
            let margin: CGFloat = 40
            let pageWidth = pageRect.width - (margin * 2)
            var currentPage = 1
            
            // Erste Seite beginnen
            context.beginPage()
            
            // Titel zeichnen
            yPosition = drawTitle(title, at: yPosition, pageWidth: pageWidth, margin: margin)
            
            // Erstellungsdatum zeichnen
            yPosition = drawGenerationDate(generationDate, at: yPosition, pageWidth: pageWidth, margin: margin)
            
            // Trennlinie
            yPosition = drawSeparator(at: yPosition, pageWidth: pageWidth, margin: margin)
            
            // Zusammenfassung
            yPosition = drawSummary(count: sortedKeynotes.count, at: yPosition, pageWidth: pageWidth, margin: margin)
            
            yPosition += 20
            
            // Alle Keynotes durchlaufen
            for (index, keynote) in sortedKeynotes.enumerated() {
                // Neue Seite beginnen, wenn nicht genug Platz (250 statt 150 wegen mehr Inhalt)
                if yPosition > pageRect.height - 250 {
                    drawFooter(pageNumber: currentPage, pageRect: pageRect, margin: margin)
                    context.beginPage()
                    currentPage += 1
                    yPosition = 60
                }
                
                yPosition = drawKeynote(
                    keynote,
                    index: index + 1,
                    at: yPosition,
                    pageWidth: pageWidth,
                    margin: margin
                )
                
                yPosition += 25
            }
            
            // Fußzeile für die letzte Seite
            drawFooter(pageNumber: currentPage, pageRect: pageRect, margin: margin)
        }
        
        return data
    }
    
    // MARK: - Drawing Functions
    
    private static func drawTitle(_ title: String, at yPosition: CGFloat, pageWidth: CGFloat, margin: CGFloat) -> CGFloat {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        
        let titleRect = CGRect(x: margin, y: yPosition, width: pageWidth, height: 40)
        title.draw(in: titleRect, withAttributes: titleAttributes)
        
        return yPosition + 40
    }
    
    private static func drawGenerationDate(_ date: Date, at yPosition: CGFloat, pageWidth: CGFloat, margin: CGFloat) -> CGFloat {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "de_DE")
        
        let dateString = "Erstellt am: \(dateFormatter.string(from: date))"
        
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        
        let dateRect = CGRect(x: margin, y: yPosition, width: pageWidth, height: 20)
        dateString.draw(in: dateRect, withAttributes: dateAttributes)
        
        return yPosition + 25
    }
    
    private static func drawSeparator(at yPosition: CGFloat, pageWidth: CGFloat, margin: CGFloat) -> CGFloat {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        
        context?.setStrokeColor(UIColor.lightGray.cgColor)
        context?.setLineWidth(1)
        context?.move(to: CGPoint(x: margin, y: yPosition))
        context?.addLine(to: CGPoint(x: margin + pageWidth, y: yPosition))
        context?.strokePath()
        
        context?.restoreGState()
        
        return yPosition + 20
    }
    
    private static func drawSummary(count: Int, at yPosition: CGFloat, pageWidth: CGFloat, margin: CGFloat) -> CGFloat {
        let summaryText = "Anzahl Auftritte: \(count)"
        
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor.black
        ]
        
        let summaryRect = CGRect(x: margin, y: yPosition, width: pageWidth, height: 20)
        summaryText.draw(in: summaryRect, withAttributes: summaryAttributes)
        
        return yPosition + 25
    }
    
    private static func drawKeynote(
        _ keynote: Keynote,
        index: Int,
        at yPosition: CGFloat,
        pageWidth: CGFloat,
        margin: CGFloat
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
        
        // Event-Name
        let headerText = keynote.eventName
        let headerRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 20)
        headerText.draw(in: headerRect, withAttributes: headerAttributes)
        currentY += 22
        
        // Datum und Status
        let dateString = dateFormatter.string(from: keynote.eventDate)
        let statusText = "\(dateString) • Status: \(keynote.status.rawValue)"
        let statusRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 18)
        statusText.draw(in: statusRect, withAttributes: secondaryAttributes)
        currentY += 18
        
        // Keynote-Titel
        if !keynote.keynoteTitle.isEmpty {
            let titleText = "Titel: \(keynote.keynoteTitle)"
            let titleRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 16)
            titleText.draw(in: titleRect, withAttributes: regularAttributes)
            currentY += 16
        }
        
        // Thema
        if !keynote.keynoteTheme.isEmpty {
            let themeText = "Thema: \(keynote.keynoteTheme)"
            let themeRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 16)
            themeText.draw(in: themeRect, withAttributes: regularAttributes)
            currentY += 16
        }
        
        // Ort
        if !keynote.location.isEmpty {
            let locationText = "Ort: \(keynote.location)"
            let locationRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 16)
            locationText.draw(in: locationRect, withAttributes: regularAttributes)
            currentY += 16
        }
        
        // Organisation
        if !keynote.clientOrganization.isEmpty {
            let orgText = "Organisation: \(keynote.clientOrganization)"
            let orgRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 16)
            orgText.draw(in: orgRect, withAttributes: regularAttributes)
            currentY += 16
        }
        
        // Primärer Kontakt
        if let contact = keynote.primaryContact, contact.hasData {
            var contactText = "Kontakt: \(contact.displayName)"
            if !contact.email.isEmpty {
                contactText += " • \(contact.email)"
            }
            if !contact.phone.isEmpty {
                contactText += " • \(contact.phone)"
            }
            let contactRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 16)
            contactText.draw(in: contactRect, withAttributes: regularAttributes)
            currentY += 16
        }
        
        // Zielpublikum
        if !keynote.targetAudience.isEmpty {
            let audienceText = "Zielpublikum: \(keynote.targetAudience)"
            let audienceRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 16)
            audienceText.draw(in: audienceRect, withAttributes: regularAttributes)
            currentY += 16
        }
        
        // Sprache
        if !keynote.language.isEmpty {
            let languageText = "Sprache: \(keynote.language)"
            let languageRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 16)
            languageText.draw(in: languageRect, withAttributes: regularAttributes)
            currentY += 16
        }
        
        // Dauer und Honorar
        let durationText = String(format: "Dauer: %.0f Min.", keynote.duration)
        let feeFormatter = NumberFormatter()
        feeFormatter.numberStyle = .currency
        feeFormatter.currencyCode = "CHF"
        let feeString = feeFormatter.string(from: keynote.agreedFee as NSDecimalNumber) ?? "CHF 0.00"
        
        let infoText = "\(durationText) • Honorar: \(feeString)"
        let infoRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 16)
        infoText.draw(in: infoRect, withAttributes: secondaryAttributes)
        currentY += 16
        
        // Anfragedatum
        let requestDateString = requestDateFormatter.string(from: keynote.requestDate)
        let requestText = "Angefragt am: \(requestDateString)"
        let requestRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 16)
        requestText.draw(in: requestRect, withAttributes: secondaryAttributes)
        currentY += 16
        
        // Notizen (falls vorhanden)
        if !keynote.notes.isEmpty {
            let notesText = "Notizen: \(keynote.notes)"
            // Verwende NSString für multi-line text drawing
            let notesNSString = notesText as NSString
            let notesRect = CGRect(x: margin + contentMargin, y: currentY, width: pageWidth - 20, height: 40)
            notesNSString.draw(in: notesRect, withAttributes: secondaryAttributes)
            currentY += 42
        }
        
        // Hintergrund zeichnen (nachträglich, damit wir die korrekte Höhe kennen)
        let totalHeight = currentY - startY + 10
        let backgroundRect = CGRect(x: margin, y: startY - 5, width: pageWidth, height: totalHeight)
        let backgroundColor = index % 2 == 0 ? UIColor(white: 0.95, alpha: 1.0) : UIColor.white
        
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setFillColor(backgroundColor.cgColor)
        
        let path = UIBezierPath(roundedRect: backgroundRect, cornerRadius: 8)
        path.fill()
        
        context?.restoreGState()
        
        // Alle Texte noch einmal zeichnen (über dem Hintergrund)
        // Event-Name
        headerText.draw(in: CGRect(x: margin + contentMargin, y: startY, width: pageWidth - 20, height: 20), withAttributes: headerAttributes)
        var redrawY = startY + 22
        
        // Datum und Status
        statusText.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 18), withAttributes: secondaryAttributes)
        redrawY += 18
        
        // Keynote-Titel
        if !keynote.keynoteTitle.isEmpty {
            let titleText = "Titel: \(keynote.keynoteTitle)"
            titleText.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 16), withAttributes: regularAttributes)
            redrawY += 16
        }
        
        // Thema
        if !keynote.keynoteTheme.isEmpty {
            let themeText = "Thema: \(keynote.keynoteTheme)"
            themeText.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 16), withAttributes: regularAttributes)
            redrawY += 16
        }
        
        // Ort
        if !keynote.location.isEmpty {
            let locationText = "Ort: \(keynote.location)"
            locationText.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 16), withAttributes: regularAttributes)
            redrawY += 16
        }
        
        // Organisation
        if !keynote.clientOrganization.isEmpty {
            let orgText = "Organisation: \(keynote.clientOrganization)"
            orgText.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 16), withAttributes: regularAttributes)
            redrawY += 16
        }
        
        // Primärer Kontakt
        if let contact = keynote.primaryContact, contact.hasData {
            var contactText = "Kontakt: \(contact.displayName)"
            if !contact.email.isEmpty {
                contactText += " • \(contact.email)"
            }
            if !contact.phone.isEmpty {
                contactText += " • \(contact.phone)"
            }
            contactText.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 16), withAttributes: regularAttributes)
            redrawY += 16
        }
        
        // Zielpublikum
        if !keynote.targetAudience.isEmpty {
            let audienceText = "Zielpublikum: \(keynote.targetAudience)"
            audienceText.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 16), withAttributes: regularAttributes)
            redrawY += 16
        }
        
        // Sprache
        if !keynote.language.isEmpty {
            let languageText = "Sprache: \(keynote.language)"
            languageText.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 16), withAttributes: regularAttributes)
            redrawY += 16
        }
        
        // Dauer und Honorar
        infoText.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 16), withAttributes: secondaryAttributes)
        redrawY += 16
        
        // Anfragedatum
        requestText.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 16), withAttributes: secondaryAttributes)
        redrawY += 16
        
        // Notizen
        if !keynote.notes.isEmpty {
            let notesText = "Notizen: \(keynote.notes)"
            let notesNSString = notesText as NSString
            notesNSString.draw(in: CGRect(x: margin + contentMargin, y: redrawY, width: pageWidth - 20, height: 40), withAttributes: secondaryAttributes)
        }
        
        return currentY
    }
    
    private static func drawFooter(pageNumber: Int, pageRect: CGRect, margin: CGFloat) {
        let footerText = "Seite \(pageNumber)"
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        
        let footerSize = footerText.size(withAttributes: footerAttributes)
        let footerRect = CGRect(
            x: (pageRect.width - footerSize.width) / 2,
            y: pageRect.height - margin / 2,
            width: footerSize.width,
            height: footerSize.height
        )
        
        footerText.draw(in: footerRect, withAttributes: footerAttributes)
    }
}
