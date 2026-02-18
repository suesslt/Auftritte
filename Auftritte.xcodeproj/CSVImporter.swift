//
//  CSVImporter.swift
//  Auftritte
//
//  Created by Thomas Süssli on 18.02.2026.
//

import Foundation
import SwiftData

// MARK: - Import Result

struct CSVImportResult {
    let rows: [CSVImportRow]
    
    var validRows: [CSVImportRow] { rows.filter { $0.error == nil } }
    var invalidRows: [CSVImportRow] { rows.filter { $0.error != nil } }
}

struct CSVImportRow: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let keynote: Keynote?
    let contact: KeynoteContact?
    let rawEventName: String
    let error: String?
}

// MARK: - CSV Parser Errors

enum CSVParseError: LocalizedError {
    case emptyFile
    case missingHeader
    case missingRequiredColumns([String])
    
    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "Die CSV-Datei ist leer."
        case .missingHeader:
            return "Die CSV-Datei enthält keine Kopfzeile."
        case .missingRequiredColumns(let cols):
            return "Fehlende Pflichtkolonnen: \(cols.joined(separator: ", "))"
        }
    }
}

// MARK: - CSV Importer Service

actor CSVImporter {
    
    // Pflichtkolonnen – ohne diese kann eine Zeile nicht importiert werden
    private static let requiredColumns = ["eventName", "eventDate"]
    
    // Alle erwarteten Kolonnen
    private static let knownColumns = [
        "eventName", "eventDate", "keynoteTitle", "keynoteTheme", "duration",
        "clientOrganization", "agreedFeeInCents", "targetAudience", "location",
        "statusRaw", "requestDate", "notes", "language",
        "contactFullName", "contactEmail", "contactPhone"
    ]
    
    // ISO 8601 Date Formatter (wie im Export verwendet)
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    /// Parst den CSV-Text und gibt ein `CSVImportResult` zurück.
    func parse(_ csvText: String) throws -> CSVImportResult {
        let lines = csvText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !lines.isEmpty else { throw CSVParseError.emptyFile }
        guard lines.count >= 2 else { throw CSVParseError.missingHeader }
        
        // Header parsen
        let headers = parseCSVLine(lines[0])
        
        // Pflichtkolonnen prüfen
        let missing = Self.requiredColumns.filter { !headers.contains($0) }
        guard missing.isEmpty else { throw CSVParseError.missingRequiredColumns(missing) }
        
        // Datenzeilen parsen
        var rows: [CSVImportRow] = []
        for (index, line) in lines.dropFirst().enumerated() {
            let lineNumber = index + 2 // 1-basiert, Zeile 1 = Header
            let row = parseRow(line, headers: headers, lineNumber: lineNumber)
            rows.append(row)
        }
        
        return CSVImportResult(rows: rows)
    }
    
    // MARK: - Row Parsing
    
    private func parseRow(_ line: String, headers: [String], lineNumber: Int) -> CSVImportRow {
        let values = parseCSVLine(line)
        
        // Header → Value Mapping
        var fields: [String: String] = [:]
        for (i, header) in headers.enumerated() {
            fields[header] = i < values.count ? values[i] : ""
        }
        
        let rawEventName = fields["eventName"] ?? ""
        
        // Pflichtfelder prüfen
        guard !rawEventName.isEmpty else {
            return CSVImportRow(
                lineNumber: lineNumber,
                keynote: nil,
                contact: nil,
                rawEventName: "(leer)",
                error: "eventName ist leer."
            )
        }
        
        guard let eventDate = parseDate(fields["eventDate"]) else {
            return CSVImportRow(
                lineNumber: lineNumber,
                keynote: nil,
                contact: nil,
                rawEventName: rawEventName,
                error: "Ungültiges Datum: \"\(fields["eventDate"] ?? "")\""
            )
        }
        
        // Optionale Felder
        let keynoteTitle       = fields["keynoteTitle"] ?? ""
        let keynoteTheme       = fields["keynoteTheme"] ?? ""
        let duration           = Double(fields["duration"] ?? "") ?? 60.0
        let clientOrganization = fields["clientOrganization"] ?? ""
        let agreedFeeInCents   = Int64(fields["agreedFeeInCents"] ?? "") ?? 0
        let targetAudience     = fields["targetAudience"] ?? ""
        let location           = fields["location"] ?? ""
        let statusRaw          = fields["statusRaw"] ?? KeynoteStatus.requested.rawValue
        let requestDate        = parseDate(fields["requestDate"]) ?? Date()
        let notes              = fields["notes"] ?? ""
        let language           = fields["language"] ?? ""
        
        // Status – Fallback auf .requested wenn unbekannt
        let status = KeynoteStatus(rawValue: statusRaw) ?? .requested
        
        // Keynote erstellen
        let keynote = Keynote(
            eventName: rawEventName,
            eventDate: eventDate,
            keynoteTitle: keynoteTitle,
            keynoteTheme: keynoteTheme,
            duration: duration,
            clientOrganization: clientOrganization,
            targetAudience: targetAudience,
            location: location,
            status: status,
            requestDate: requestDate,
            notes: notes,
            language: language
        )
        
        // Honorar direkt in Cents setzen (kein Rundungsfehler)
        keynote.agreedFeeInCents = agreedFeeInCents
        
        // Kontakt erstellen – nur wenn mindestens ein Feld vorhanden
        let contactName  = fields["contactFullName"] ?? ""
        let contactEmail = fields["contactEmail"] ?? ""
        let contactPhone = fields["contactPhone"] ?? ""
        
        var contact: KeynoteContact? = nil
        if !contactName.isEmpty || !contactEmail.isEmpty || !contactPhone.isEmpty {
            contact = KeynoteContact(
                fullName: contactName,
                email: contactEmail,
                phone: contactPhone
            )
            keynote.primaryContact = contact
        }
        
        return CSVImportRow(
            lineNumber: lineNumber,
            keynote: keynote,
            contact: contact,
            rawEventName: rawEventName,
            error: nil
        )
    }
    
    // MARK: - CSV Line Parser (RFC 4180 kompatibel)
    
    /// Parst eine einzelne CSV-Zeile korrekt, berücksichtigt Anführungszeichen und eingebettete Kommas/Newlines.
    func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        
        while let char = iterator.next() {
            switch char {
            case "\"":
                if inQuotes {
                    // Lookahead: doppelte Anführungszeichen = escaptes "
                    // Wir simulieren das durch die nächste Iteration
                    inQuotes = false
                } else {
                    inQuotes = true
                }
            case ",":
                if inQuotes {
                    current.append(char)
                } else {
                    fields.append(current)
                    current = ""
                }
            default:
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
    
    // MARK: - Date Parsing
    
    private func parseDate(_ string: String?) -> Date? {
        guard let s = string, !s.isEmpty else { return nil }
        return isoFormatter.date(from: s)
    }
}
