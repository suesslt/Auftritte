//
//  CSVExporter.swift
//  Auftritte
//
//  Created by Thomas Süssli on 18.02.2026.
//

import Foundation

// MARK: - CSV Exporter Service

actor CSVExporter {

    // Exakt dieselbe Kolonnen-Reihenfolge wie in CSVImporter.knownColumns
    private static let headers = [
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
        "contactFullName",
        "contactEmail",
        "contactPhone"
    ]

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Public API

    /// Konvertiert eine Liste von Keynotes in einen RFC-4180-konformen CSV-String.
    func export(_ keynotes: [Keynote]) -> String {
        var lines: [String] = []

        // Header-Zeile
        lines.append(Self.headers.map { csvField($0) }.joined(separator: ","))

        // Daten-Zeilen
        for keynote in keynotes {
            lines.append(row(for: keynote))
        }

        return lines.joined(separator: "\r\n")
    }

    /// Schreibt den CSV-String in eine temporäre Datei und gibt deren URL zurück.
    /// Die Datei wird im temporären Verzeichnis abgelegt und bei Bedarf überschrieben.
    func exportToFile(_ keynotes: [Keynote]) throws -> URL {
        let csvText = export(keynotes)

        let fileName = "Auftritte_\(fileTimestamp()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        guard let data = csvText.data(using: .utf8) else {
            throw CSVExportError.encodingFailed
        }

        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Private Helpers

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
            keynote.contactFullName,
            keynote.contactEmail,
            keynote.contactPhone
        ]

        return fields.map { csvField($0) }.joined(separator: ",")
    }

    /// Escaped einen einzelnen Wert gemäss RFC 4180:
    /// Enthält der Wert Kommas, Anführungszeichen oder Zeilenumbrüche,
    /// wird er in Anführungszeichen eingeschlossen;
    /// vorhandene Anführungszeichen werden verdoppelt.
    private func csvField(_ value: String) -> String {
        let needsQuoting = value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")

        if needsQuoting {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter.string(from: Date())
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
