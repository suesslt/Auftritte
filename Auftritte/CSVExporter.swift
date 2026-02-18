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

    private func buildCSV(_ keynotes: [Keynote]) -> String {
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
            keynote.contactFullName,
            keynote.contactEmail,
            keynote.contactPhone
        ]
        return fields.map { csvField($0) }.joined(separator: ",")
    }

    /// Escaped einen Wert gemäss RFC 4180.
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
