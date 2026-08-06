//
//  CalendarReconciliation.swift
//  Auftritte
//
//  Engine für den Abgleich zwischen Auftritten und dem Apple Kalender.
//  Bewusst EventKit-frei gehalten (Events als Snapshots), damit die Logik testbar ist.
//
//  Zuordnung rein über Zeiten: Event-IDs sind nicht geräteübergreifend stabil,
//  und der Zielkalender enthält ausschliesslich Auftritte. Gepaart wird über
//  identische Startzeitpunkte oder denselben Kalendertag in der Zeitzone des
//  Events — nie in der Gerätezeitzone —, damit der Abgleich auch auf Reisen in
//  einer anderen Zeitzone korrekt bleibt.
//

import Score
import Foundation
import EventKit

// MARK: - Event-Snapshot

/// Snapshot eines Kalender-Events; `id` ist occurrence-eindeutig,
/// da wiederkehrende Events denselben `eventIdentifier` teilen.
struct ReconciliationEvent: Identifiable, Hashable {
    let eventIdentifier: String
    let title: String
    let start: Date
    let end: Date
    /// Zeitzone des Events (z.B. Europe/Zurich); nil bei «floating» Events.
    /// Massgeblich für den Tagesvergleich, damit der Abgleich unabhängig von der
    /// Zeitzone ist, in der das Gerät gerade steht.
    let timeZone: TimeZone?
    let location: String?
    let notes: String?

    var id: String { "\(eventIdentifier)|\(start.timeIntervalSinceReferenceDate)" }
}

extension ReconciliationEvent {
    init(event: EKEvent) {
        self.init(
            eventIdentifier: event.eventIdentifier ?? "",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            timeZone: event.timeZone,
            location: event.location,
            notes: event.notes
        )
    }
}

// MARK: - Ergebnis

struct ReconciliationResult {
    struct MatchedPair: Identifiable {
        let keynote: Keynote
        let event: ReconciliationEvent
        /// true bei Fuzzy-Match ohne gespeicherte Event-ID —
        /// beim Übernehmen wird `keynote.calendarEventID` verknüpft.
        let needsLink: Bool

        var id: String { event.id }
    }

    var onlyInCalendar: [ReconciliationEvent] = []   // Gruppe 1: nur im Kalender
    var timeMismatch: [MatchedPair] = []             // Gruppe 2: Startzeit weicht ab
    var missingInCalendar: [Keynote] = []            // Gruppe 3: fehlt im Kalender
    var matching: [MatchedPair] = []                 // Gruppe 4: übereinstimmend

    var pendingLinkCount: Int { (timeMismatch + matching).filter(\.needsLink).count }

    var isEmpty: Bool {
        onlyInCalendar.isEmpty && timeMismatch.isEmpty && missingInCalendar.isEmpty && matching.isEmpty
    }
}

// MARK: - Engine

enum ReconciliationEngine {

    static let saveTheDatePrefix = "SAVE THE DATE:"
    static let horizonYears = 2

    /// Gleicher Auftritt mit gleicher Zeit: Startzeitpunkte liegen weniger als eine Minute auseinander.
    static let exactMatchTolerance: TimeInterval = 60

    /// Gleicht Auftritte gegen Kalender-Event-Snapshots ab — rein über die Zeiten,
    /// da Event-IDs nicht geräteübergreifend stabil sind und der Zielkalender
    /// ausschliesslich Auftritte enthält.
    ///
    /// Ein Paar gilt als derselbe Auftritt, wenn die Startzeitpunkte praktisch identisch
    /// sind («Übereinstimmend») oder auf denselben Kalendertag in der Zeitzone des
    /// Events fallen («Zeit weicht ab»). Der Tagesvergleich nutzt bewusst die Zeitzone
    /// des Events — nicht die des Geräts —, damit der Abgleich auch auf Reisen in einer
    /// anderen Zeitzone dasselbe Ergebnis liefert. Zuordnung gierig nach kleinstem Zeitabstand.
    static func reconcile(keynotes: [Keynote], events: [ReconciliationEvent], now: Date = .now) -> ReconciliationResult {
        let rangeEnd = Calendar.home.date(byAdding: .year, value: horizonYears, to: now) ?? now

        let candidates = keynotes
            .filter { keynote in
                keynote.eventDate >= now &&
                keynote.eventDate <= rangeEnd &&
                !keynote.inAbklaerung &&
                relevantStatuses.contains(keynote.status)
            }
            .sorted { $0.eventDate < $1.eventDate }

        struct Pairing {
            let keynoteIndex: Int
            let eventIndex: Int
            let distance: TimeInterval
        }

        var pairings: [Pairing] = []
        for (keynoteIndex, keynote) in candidates.enumerated() {
            for (eventIndex, event) in events.enumerated() {
                let distance = abs(event.start.timeIntervalSince(keynote.eventDate))
                if distance < exactMatchTolerance || isSameDay(keynote: keynote, event: event) {
                    pairings.append(Pairing(keynoteIndex: keynoteIndex, eventIndex: eventIndex, distance: distance))
                }
            }
        }
        pairings.sort { $0.distance < $1.distance }

        var result = ReconciliationResult()
        var pairedKeynotes = Set<Int>()
        var pairedEvents = Set<Int>()

        for pairing in pairings
        where !pairedKeynotes.contains(pairing.keynoteIndex) && !pairedEvents.contains(pairing.eventIndex) {
            pairedKeynotes.insert(pairing.keynoteIndex)
            pairedEvents.insert(pairing.eventIndex)

            let keynote = candidates[pairing.keynoteIndex]
            let event = events[pairing.eventIndex]
            // ID wird nur noch als Ergebnis gepflegt (für Update/Löschen auf diesem Gerät),
            // nie als Match-Kriterium: fehlt sie oder stimmt sie nicht, wird neu verknüpft.
            let pair = ReconciliationResult.MatchedPair(
                keynote: keynote,
                event: event,
                needsLink: keynote.calendarEventID != event.eventIdentifier
            )
            if pairing.distance < exactMatchTolerance {
                result.matching.append(pair)
            } else {
                result.timeMismatch.append(pair)
            }
        }

        result.matching.sort { $0.keynote.eventDate < $1.keynote.eventDate }
        result.timeMismatch.sort { $0.keynote.eventDate < $1.keynote.eventDate }
        result.missingInCalendar = candidates.enumerated()
            .filter { !pairedKeynotes.contains($0.offset) }
            .map(\.element)
        result.onlyInCalendar = events.enumerated()
            .filter { !pairedEvents.contains($0.offset) }
            .map(\.element)
            .sorted { $0.start < $1.start }
        return result
    }

    /// Tagesvergleich in der Zeitzone des Events (Fallback: Heimatzeitzone bei
    /// «floating» Events). So zählt z.B. ein Auftritt, der in der App auf Mitternacht
    /// des 11.08. steht, und ein Event am 11.08. um 17:30 Europe/Zurich als dasselbe
    /// Paar — egal, in welcher Zeitzone das Gerät beim Abgleich gerade steht.
    private static func isSameDay(keynote: Keynote, event: ReconciliationEvent) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = event.timeZone ?? .home
        return calendar.isDate(event.start, inSameDayAs: keynote.eventDate)
    }

    /// Auftritte, für die ein Kalendereintrag erwartet wird: Datum bestätigt, aber noch
    /// nicht abgeschlossen. `requested` hat noch kein fixes Datum, `cancelled` ist raus,
    /// `completed/invoiced/closed` sind erledigte Vorgänge ohne Kalender-Anspruch.
    private static let relevantStatuses: Set<KeynoteStatus> = [
        .dateConfirmedFeeOffered, .feeConfirmed, .contentAgreed, .contractSigned
    ]

    // MARK: - Übernahme (Gruppe 1)

    /// Erstellt aus einem Kalender-Event einen neuen Auftritt.
    /// Hinweis: Bei mehreren übernommenen Occurrences desselben Serien-Events
    /// erhalten alle Auftritte dieselbe `calendarEventID` (EventKit vergibt pro Serie nur eine).
    static func makeKeynote(from event: ReconciliationEvent) -> Keynote {
        let title = displayTitle(for: event)
        let minutes = max(event.end.timeIntervalSince(event.start) / 60, 15)
        return Keynote(
            eventName: title,
            eventDate: event.start,
            keynoteTitle: title,
            duration: minutes,
            location: event.location ?? "",
            status: .dateConfirmedFeeOffered,
            calendarEventID: event.eventIdentifier,
            notes: event.notes ?? ""
        )
    }

    /// Event-Titel ohne «SAVE THE DATE:»-Präfix, Original-Schreibweise erhalten.
    static func displayTitle(for event: ReconciliationEvent) -> String {
        var text = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: saveTheDatePrefix, options: [.caseInsensitive, .anchored]) {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
