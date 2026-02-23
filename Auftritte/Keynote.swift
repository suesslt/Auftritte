//
//  Auftritte.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import Foundation
import SwiftData

@Model
final class Keynote {
    var eventName: String = ""
    var eventDate: Date = Date()
    var keynoteTitle: String = ""
    var keynoteTheme: String = ""
    var duration: Double = 60 // in Minuten (CloudKit-kompatibel)
    var clientOrganization: String = ""
    var contactFullName: String = ""
    var contactEmail: String = ""
    var contactPhone: String = ""
    var contactLocalID: String? // Lokale CNContact-ID für "In Kontakte öffnen" (gerätespezifisch)
    var agreedFeeInCents: Int64 = 0 // Honorar in Cents/Rappen gespeichert (Decimal geht nicht in CloudKit)
    var targetAudience: String = ""
    var location: String = ""
    var statusRaw: String = KeynoteStatus.requested.rawValue
    var requestDate: Date = Date()
    var calendarEventID: String? // EventKit Event Identifier
    var notes: String = ""
    var language: String = "" // Sprache des Auftritts
    var inAbklaerung: Bool = false
    var pendenzRaw: String = Pendenz.speaker.rawValue
    
    // Computed properties für Kontakt-Darstellung (analog zu KeynoteContact)
    var contactDisplayName: String {
        contactFullName.isEmpty ? "Unbekannter Kontakt" : contactFullName
    }
    
    var contactHasData: Bool {
        !contactFullName.isEmpty || !contactEmail.isEmpty || !contactPhone.isEmpty
    }
    
    // Computed property für Status
    var status: KeynoteStatus {
        get {
            KeynoteStatus(rawValue: statusRaw) ?? .requested
        }
        set {
            statusRaw = newValue.rawValue
        }
    }
    
    // Computed property für Pendenz
    var pendenz: Pendenz {
        get {
            Pendenz(rawValue: pendenzRaw) ?? .speaker
        }
        set {
            pendenzRaw = newValue.rawValue
        }
    }

    // Computed property für Section-Zuordnung
    var section: KeynoteSection {
        let erledigtStatuses: Set<KeynoteStatus> = [.closed, .cancelled, .paid]
        if erledigtStatuses.contains(status) {
            return .erledigt
        }
        if inAbklaerung {
            return .datumInAbklaerung
        }
        switch pendenz {
        case .speaker: return .pendenzSpeaker
        case .client: return .pendenzClient
        case .none: return .auftrittsbereit
        }
    }

    // Computed property für Honorar mit Decimal-Kompatibilität
    var agreedFee: Decimal {
        get {
            Decimal(agreedFeeInCents) / Decimal(100)
        }
        set {
            var result = newValue * Decimal(100)
            var rounded = Decimal()
            NSDecimalRound(&rounded, &result, 0, .plain)
            agreedFeeInCents = Int64(truncating: rounded as NSDecimalNumber)
        }
    }
    
    init(
        eventName: String = "",
        eventDate: Date = Date(),
        keynoteTitle: String = "",
        keynoteTheme: String = "",
        duration: Double = 60,
        clientOrganization: String = "",
        contactFullName: String = "",
        contactEmail: String = "",
        contactPhone: String = "",
        contactLocalID: String? = nil,
        agreedFee: Decimal = 0,
        targetAudience: String = "",
        location: String = "",
        status: KeynoteStatus = .requested,
        requestDate: Date = Date(),
        calendarEventID: String? = nil,
        notes: String = "",
        language: String = "",
        inAbklaerung: Bool = false,
        pendenz: Pendenz = .speaker
    ) {
        self.eventName = eventName
        self.eventDate = eventDate
        self.keynoteTitle = keynoteTitle
        self.keynoteTheme = keynoteTheme
        self.duration = duration
        self.clientOrganization = clientOrganization
        self.contactFullName = contactFullName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.contactLocalID = contactLocalID

        var result = agreedFee * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, 0, .plain)
        self.agreedFeeInCents = Int64(truncating: rounded as NSDecimalNumber)

        self.targetAudience = targetAudience
        self.location = location
        self.statusRaw = status.rawValue
        self.requestDate = requestDate
        self.calendarEventID = calendarEventID
        self.notes = notes
        self.language = language
        self.inAbklaerung = inAbklaerung
        self.pendenzRaw = pendenz.rawValue
    }
}
