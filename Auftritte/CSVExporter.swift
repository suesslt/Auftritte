//
//  CSVExporter.swift
//  Auftritte
//
//  Created by Thomas Süssli on 18.02.2026.
//

import Foundation
import Score

// MARK: - CSV Exporter Service

actor KeynoteCSVExporter {

    // Exakt dieselbe Kolonnen-Reihenfolge wie in KeynoteCSVImporter.knownColumns
    static let headers = [
        "eventName",
        "eventDate",
        "keynoteTitle",
        "keynoteTheme",
        "duration",
        "clientOrganization",
        "agreedFeeInCents",
        "targetAudience",
        "location",
        "statusRaw",
        "requestDate",
        "notes",
        "language",
        "contactFirstName",
        "contactLastName",
        "contactFullName",
        "contactEmail",
        "contactPhone",
        "inAbklaerung",
        "pendenzRaw",
        "pendenzNote",
        "pendenzErledigt",
        "attendeeCount",
        "distanceKm"
    ]

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Public API

    /// Schreibt die CSV in das Documents-Verzeichnis und gibt die URL zurück.
    /// Das Documents-Verzeichnis ist für UIActivityViewController immer erreichbar.
    func exportToDocuments(_ keynotes: [Keynote]) throws -> URL {
        let csv = buildCSV(keynotes)

        guard let data = csv.data(using: .utf8) else {
            throw CSVExportError.encodingFailed
        }

        let filename = "Auftritte_\(fileTimestamp()).csv"
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let fileURL = documentsURL.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - Private Helpers

    /// Erzeugt CSV-Text aus den übergebenen Keynotes. Intern für Tests sichtbar.
    func buildCSV(_ keynotes: [Keynote]) -> String {
        var lines: [String] = []
        lines.append(Self.headers.map { csvField($0) }.joined(separator: ","))
        for keynote in keynotes {
            lines.append(row(for: keynote))
        }
        // RFC 4180: CRLF als Zeilentrennzeichen
        return lines.joined(separator: "\r\n")
    }

    private func row(for keynote: Keynote) -> String {
        let fields: [String] = [
            keynote.eventName,
            isoFormatter.string(from: keynote.eventDate),
            keynote.keynoteTitle,
            keynote.keynoteTheme,
            String(keynote.duration),
            keynote.clientOrganization,
            String(keynote.agreedFeeInCents),
            keynote.targetAudience,
            keynote.location,
            keynote.statusRaw,
            isoFormatter.string(from: keynote.requestDate),
            keynote.notes,
            keynote.language,
            keynote.contactFirstName,
            keynote.contactLastName,
            Self.combinedContactName(keynote),
            keynote.contactEmail,
            keynote.contactPhone,
            String(keynote.inAbklaerung),
            keynote.pendenzRaw,
            keynote.pendenzNote,
            String(keynote.pendenzErledigt),
            keynote.attendeeCount.map(String.init) ?? "",
            keynote.distanceKm.map(String.init) ?? ""
        ]
        return fields.map { csvField($0) }.joined(separator: ",")
    }

    /// Escaped einen Wert gemäss RFC 4180 — seit score v2.2.0 delegiert an die
    /// geteilte Implementierung (Format-Vertrag: Komma-Separator, CRLF bleibt hier).
    private func csvField(_ value: String) -> String {
        Score.CSVExporter.escapeCSV(value, separator: ",")
    }

    private func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        formatter.timeZone = .home
        return formatter.string(from: Date())
    }

    /// Kombiniert Vorname und Nachname zu "Vorname Name". Fällt auf Legacy `contactFullName` zurück.
    nonisolated static func combinedContactName(_ keynote: Keynote) -> String {
        let first = keynote.contactFirstName.trimmingCharacters(in: .whitespaces)
        let last  = keynote.contactLastName.trimmingCharacters(in: .whitespaces)
        let combined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return combined.isEmpty ? keynote.contactFullName : combined
    }
}

// MARK: - Export Errors

enum CSVExportError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Die CSV-Datei konnte nicht als UTF-8 kodiert werden."
        }
    }
}
