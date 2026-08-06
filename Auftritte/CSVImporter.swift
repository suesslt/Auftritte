//
//  CSVImporter.swift
//  Auftritte
//
//  Created by Thomas Süssli on 18.02.2026.
//

import Foundation
import Score
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

/// Seit der Score-CSV-Adoption (score v2.2.0, 2026-08-06) übernimmt
/// `Score.CSVImporter` das RFC-4180-Parsen (Quotes, Multiline-Felder, BOM);
/// hier verbleibt nur das Keynote-Mapping. Die Header sind ein Format-Vertrag
/// mit alten Exporten — deshalb `lowercasedHeaders: false` und fester
/// Komma-Separator.
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
        "attendeeCount", "distanceKm"
    ]

    /// Migrations-Mapping für obsolete Status-Werte (alte CSV-Exporte).
    /// Identisch mit `AuftritteApp.runStatusMigration()`.
    static func mappedStatusRaw(_ raw: String) -> String {
        switch raw {
        case "Durchgeführt und in Rechnung gestellt": return KeynoteStatus.completed.rawValue
        case "Feedback angefragt":                    return KeynoteStatus.closed.rawValue
        case "Bezahlt":                               return KeynoteStatus.closed.rawValue
        case "Abgesagt":                              return KeynoteStatus.cancelled.rawValue
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
        do {
            // Der Transform reicht die Zeile durch — die Fehlerbehandlung je Zeile
            // (Keynote? + error-Text) bleibt Sache von `parseRow`.
            let parsed = try Score.CSVImporter.parseWithErrors(
                from: csvText, separator: ",",
                required: Self.requiredColumns,
                lowercasedHeaders: false
            ) { row in row }

            var rows: [CSVImportRow] = []
            for (index, fields) in parsed.valid.enumerated() {
                let lineNumber = index + 2 // 1-basiert, Zeile 1 = Header
                rows.append(parseRow(fields: fields, lineNumber: lineNumber))
            }
            return CSVImportResult(rows: rows)
        } catch Score.CSVImporter.CSVImportError.missingColumns(let cols) {
            throw CSVParseError.missingRequiredColumns(cols)
        } catch Score.CSVImporter.CSVImportError.emptyFile {
            // Score unterscheidet «leer» nicht von «nur Kopfzeile» — hier schon.
            let hasAnyContent = csvText.contains(where: { !$0.isWhitespace })
            throw hasAnyContent ? CSVParseError.missingHeader : CSVParseError.emptyFile
        }
    }

    // MARK: - Row Parsing

    private func parseRow(fields: [String: String], lineNumber: Int) -> CSVImportRow {
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
        let inAbklaerung = Score.CSVImporter.parseFlag(fields["inAbklaerung"])
        let pendenzRawValue = fields["pendenzRaw"] ?? Pendenz.speaker.rawValue
        let pendenz = Pendenz(rawValue: pendenzRawValue) ?? .speaker
        let pendenzNote = fields["pendenzNote"] ?? ""
        let pendenzErledigt = Score.CSVImporter.parseFlag(fields["pendenzErledigt"])

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

        // Distanz in km (optional)
        keynote.distanceKm = Int(fields["distanceKm"] ?? "")

        return CSVImportRow(
            lineNumber: lineNumber,
            keynote: keynote,
            rawEventName: rawEventName,
            error: nil
        )
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
