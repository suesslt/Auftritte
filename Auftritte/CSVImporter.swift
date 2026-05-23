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

actor KeynoteCSVImporter {
    
    // Pflichtkolonnen – ohne diese kann eine Zeile nicht importiert werden
    private static let requiredColumns = ["eventName", "eventDate"]
    
    // Alle erwarteten Kolonnen
    private static let knownColumns = [
        "eventName", "eventDate", "keynoteTitle", "keynoteTheme", "duration",
        "clientOrganization", "agreedFeeInCents", "targetAudience", "location",
        "statusRaw", "requestDate", "notes", "language",
        "contactFirstName", "contactLastName", "contactFullName",
        "contactEmail", "contactPhone",
        "inAbklaerung", "pendenzRaw", "pendenzNote", "pendenzErledigt",
        "attendeeCount"
    ]

    /// Migrations-Mapping für obsolete Status-Werte (alte CSV-Exporte).
    /// Identisch mit `AuftritteApp.runStatusMigration()`.
    static func mappedStatusRaw(_ raw: String) -> String {
        switch raw {
        case "Durchgeführt und in Rechnung gestellt": return KeynoteStatus.completed.rawValue
        case "Feedback angefragt":                    return KeynoteStatus.closed.rawValue
        default:                                      return raw
        }
    }
    
    // ISO 8601 Date Formatter (wie im Export verwendet)
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    /// Parst den CSV-Text und gibt ein `CSVImportResult` zurück.
    func parse(_ csvText: String) throws -> CSVImportResult {
        // Gesamten Text RFC-4180-konform in Zeilen (Records) aufteilen –
        // dabei werden Zeilenumbrüche innerhalb von Anführungszeichen NICHT als Trenner behandelt.
        let records = parseCSVRecords(csvText)
        
        guard !records.isEmpty else { throw CSVParseError.emptyFile }
        guard records.count >= 2 else { throw CSVParseError.missingHeader }
        
        // Header parsen
        let headers = records[0]
        
        // Pflichtkolonnen prüfen
        let missing = Self.requiredColumns.filter { !headers.contains($0) }
        guard missing.isEmpty else { throw CSVParseError.missingRequiredColumns(missing) }
        
        // Datenzeilen parsen
        var rows: [CSVImportRow] = []
        for (index, fields) in records.dropFirst().enumerated() {
            let lineNumber = index + 2 // 1-basiert, Zeile 1 = Header
            let row = parseRow(fields: fields, headers: headers, lineNumber: lineNumber)
            rows.append(row)
        }
        
        return CSVImportResult(rows: rows)
    }
    
    // MARK: - Row Parsing
    
    private func parseRow(fields values: [String], headers: [String], lineNumber: Int) -> CSVImportRow {
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
                rawEventName: "(leer)",
                error: "eventName ist leer."
            )
        }
        
        guard let eventDate = parseDate(fields["eventDate"]) else {
            return CSVImportRow(
                lineNumber: lineNumber,
                keynote: nil,
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
        let statusRaw          = Self.mappedStatusRaw(fields["statusRaw"] ?? KeynoteStatus.requested.rawValue)
        let requestDate        = parseDate(fields["requestDate"]) ?? Date()
        let notes              = fields["notes"] ?? ""
        let language           = fields["language"] ?? ""

        // Status – Fallback auf .requested wenn unbekannt
        let status = KeynoteStatus(rawValue: statusRaw) ?? .requested

        // Neue Felder
        let inAbklaerung = (fields["inAbklaerung"] ?? "false").lowercased() == "true"
        let pendenzRawValue = fields["pendenzRaw"] ?? Pendenz.speaker.rawValue
        let pendenz = Pendenz(rawValue: pendenzRawValue) ?? .speaker
        let pendenzNote = fields["pendenzNote"] ?? ""
        let pendenzErledigt = (fields["pendenzErledigt"] ?? "false").lowercased() == "true"

        // Kontaktnamen: explizite Spalten bevorzugt, sonst Heuristik aus contactFullName
        let explicitFirst = fields["contactFirstName"] ?? ""
        let explicitLast  = fields["contactLastName"] ?? ""
        let importedFirstName: String
        let importedLastName: String
        if !explicitFirst.isEmpty || !explicitLast.isEmpty {
            importedFirstName = explicitFirst
            importedLastName  = explicitLast
        } else {
            (importedFirstName, importedLastName) = Self.splitContactName(fields["contactFullName"] ?? "")
        }
        let keynote = Keynote(
            eventName: rawEventName,
            eventDate: eventDate,
            keynoteTitle: keynoteTitle,
            keynoteTheme: keynoteTheme,
            duration: duration,
            clientOrganization: clientOrganization,
            contactFirstName: importedFirstName,
            contactLastName: importedLastName,
            contactFullName: "",
            contactEmail: fields["contactEmail"] ?? "",
            contactPhone: fields["contactPhone"] ?? "",
            targetAudience: targetAudience,
            location: location,
            status: status,
            requestDate: requestDate,
            notes: notes,
            language: language,
            inAbklaerung: inAbklaerung,
            pendenz: pendenz,
            pendenzNote: pendenzNote,
            pendenzErledigt: pendenzErledigt
        )
        
        // Honorar direkt in Cents setzen (kein Rundungsfehler)
        keynote.agreedFeeInCents = agreedFeeInCents

        // Anzahl Zuhörer (optional)
        keynote.attendeeCount = Int(fields["attendeeCount"] ?? "")
        
        return CSVImportRow(
            lineNumber: lineNumber,
            keynote: keynote,
            rawEventName: rawEventName,
            error: nil
        )
    }
    
    // MARK: - CSV Parser (RFC 4180 konform)

    /// Parst den gesamten CSV-Text in Records (Zeilen) und Felder.
    /// Zeilenumbrüche innerhalb von Anführungszeichen werden korrekt ignoriert.
    /// Leere Records (z. B. abschliessende Leerzeile) werden übersprungen.
    private func parseCSVRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var currentRecord: [String] = []
        var currentField = ""
        var inQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]

            if inQuotes {
                if char == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex && text[next] == "\"" {
                        // "" → escaptes Anführungszeichen
                        currentField.append("\"")
                        index = text.index(after: next)
                        continue
                    } else {
                        // Schliessende Anführungszeichen
                        inQuotes = false
                    }
                } else {
                    // Alles innerhalb von Quotes – auch Kommas und Newlines – direkt anhängen
                    currentField.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRecord.append(currentField)
                    currentField = ""
                case "\r\n", "\n", "\r":
                    // Zeilenende: aktuelles Feld und Record abschliessen
                    // \r\n: das \n wird in der nächsten Iteration übersprungen
                    currentRecord.append(currentField)
                    currentField = ""
                    if !currentRecord.allSatisfy({ $0.isEmpty }) {
                        records.append(currentRecord)
                    }
                    currentRecord = []
                    // \r\n überbrücken
                    if char == "\r" {
                        let next = text.index(after: index)
                        if next < text.endIndex && text[next] == "\n" {
                            index = text.index(after: next)
                            continue
                        }
                    }
                default:
                    currentField.append(char)
                }
            }

            index = text.index(after: index)
        }

        // Letztes Feld und Record nicht vergessen
        currentRecord.append(currentField)
        if !currentRecord.allSatisfy({ $0.isEmpty }) {
            records.append(currentRecord)
        }

        return records
    }

    /// Parst eine einzelne CSV-Zeile (ohne Zeilenumbrüche in Feldern).
    /// Wird nur noch für isolierte Zeilen benötigt.
    func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]

            if char == "\"" {
                if inQuotes {
                    let next = line.index(after: index)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        index = line.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }

            index = line.index(after: index)
        }

        fields.append(current)
        return fields
    }
    
    // MARK: - Date Parsing
    
    private func parseDate(_ string: String?) -> Date? {
        guard let s = string, !s.isEmpty else { return nil }
        return isoFormatter.date(from: s)
    }

    // MARK: - Contact Name Splitting

    /// Splittet einen vollständigen Namen heuristisch in (Vorname, Nachname).
    /// Erstes Wort = Vorname, Rest = Nachname. Bei nur einem Wort gilt es als Vorname.
    nonisolated static func splitContactName(_ fullName: String) -> (firstName: String, lastName: String) {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return ("", "") }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        return (trimmed, "")
    }
}
