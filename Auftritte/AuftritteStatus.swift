//
//  KeynoteStatus.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import Foundation
import SwiftUI

// MARK: - Pendenz

enum Pendenz: String, Codable, CaseIterable, Identifiable {
    case speaker = "Speaker"
    case client = "Auftraggeber"
    case none = "Keine"

    var id: String { rawValue }
}

// MARK: - Keynote Section

enum KeynoteSection: Int, CaseIterable, Identifiable {
    case datumInAbklaerung = 0
    case pendenzSpeaker = 1
    case pendenzClient = 2
    case auftrittsbereit = 3
    case erledigt = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .datumInAbklaerung: return "Datum in Abklärung"
        case .pendenzSpeaker: return "Pendenz beim Speaker"
        case .pendenzClient: return "Pendenz beim Auftraggeber"
        case .auftrittsbereit: return "Auftrittsbereit"
        case .erledigt: return "Erledigt"
        }
    }
}

// MARK: - Sidebar Category

enum SidebarCategory: String, CaseIterable, Identifiable {
    case vereinbarteAuftritte = "Kommende Auftritte"
    case pendenzSpeaker = "Pendenzen"
    case datumUngeklaert = "Datum noch nicht geklärt"
    case durchgefuehrt = "Vergangene Auftritte"
    case alleAuftritte = "Alle Auftritte"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vereinbarteAuftritte: return "calendar.badge.checkmark"
        case .pendenzSpeaker: return "person.badge.clock"
        case .datumUngeklaert: return "calendar.badge.exclamationmark"
        case .durchgefuehrt: return "checkmark.circle.fill"
        case .alleAuftritte: return "rectangle.stack.fill"
        }
    }
}

// MARK: - Keynote Status

enum KeynoteStatus: String, Codable, CaseIterable, Identifiable {
    case requested = "Angefragt"
    case dateConfirmedFeeOffered = "Termin bestätigt, Honorar offeriert"
    case feeConfirmed = "Honorar bestätigt"
    case contentAgreed = "Thema, Inhalt und Zielpublikum vereinbart"
    case contractSigned = "Vertrag erstellt und Zustande gekommen"
    case completed = "Durchgeführt"
    case invoiced = "Rechnung gestellt"
    case closed = "Abgeschlossen"
    case cancelled = "Abgebrochen"

    var id: String { rawValue }

    var nextStatus: [KeynoteStatus] {
        switch self {
        case .requested:
            return [.dateConfirmedFeeOffered, .cancelled]
        case .dateConfirmedFeeOffered:
            return [.feeConfirmed, .cancelled]
        case .feeConfirmed:
            return [.contentAgreed, .cancelled]
        case .contentAgreed:
            return [.contractSigned, .cancelled]
        case .contractSigned:
            return [.completed, .cancelled]
        case .completed:
            return [.invoiced, .cancelled]
        case .invoiced:
            return [.closed, .cancelled]
        case .closed, .cancelled:
            return []
        }
    }

    var color: Color {
        switch self {
        case .requested:
            return .blue
        case .dateConfirmedFeeOffered:
            return .cyan
        case .feeConfirmed:
            return .mint
        case .contentAgreed:
            return .teal
        case .contractSigned:
            return .green
        case .completed:
            return .yellow
        case .invoiced:
            return .orange
        case .closed:
            return .gray
        case .cancelled:
            return .red
        }
    }
}
