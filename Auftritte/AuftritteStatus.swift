//
//  KeynoteStatus.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import Foundation
import SwiftUI

enum KeynoteStatus: String, Codable, CaseIterable, Identifiable {
    case requested = "Angefragt"
    case dateConfirmedFeeOffered = "Termin bestätigt, Honorar offeriert"
    case feeConfirmed = "Honorar bestätigt"
    case contentAgreed = "Thema, Inhalt und Zielpublikum vereinbart"
    case contractSigned = "Vertrag erstellt und Zustande gekommen"
    case completedInvoiced = "Durchgeführt und in Rechnung gestellt"
    case paid = "Bezahlt"
    case feedbackRequested = "Feedback angefragt"
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
            return [.completedInvoiced, .cancelled]
        case .completedInvoiced:
            return [.paid, .cancelled]
        case .paid:
            return [.feedbackRequested, .closed]
        case .feedbackRequested:
            return [.closed]
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
        case .completedInvoiced:
            return .yellow
        case .paid:
            return .orange
        case .feedbackRequested:
            return .purple
        case .closed:
            return .gray
        case .cancelled:
            return .red
        }
    }
}
