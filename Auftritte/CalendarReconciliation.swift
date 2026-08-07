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
import SwiftData

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

    /// Alle ungepaarten Kandidaten unabhängig vom Status — Basis für den stillen
    /// Auto-Abbruch; `missingInCalendar` bleibt die kuratierte Teilmenge für die UI.
    var unpairedCandidates: [Keynote] = []

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

        // Paarungs-Kandidaten: alle Auftritte mit bekanntem Datum im Zeitraum, ausser
        // abgebrochene. Bewusst breiter als «erwartet einen Kalendereintrag»
        // (relevantStatuses): Auch ein erst angefragter Auftritt muss sein Kalender-Event
        // finden — sonst erschiene das Event als «nur im Kalender» und würde beim
        // Übernehmen dupliziert.
        let candidates = keynotes
            .filter { keynote in
                keynote.eventDate >= now &&
                keynote.eventDate <= rangeEnd &&
                !keynote.inAbklaerung &&
                keynote.status != .cancelled
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
        result.unpairedCandidates = candidates.enumerated()
            .filter { !pairedKeynotes.contains($0.offset) }
            .map(\.element)
        // «Fehlt im Kalender» nur für Auftritte, die einen Eintrag erwarten — ein bloss
        // angefragter Auftritt ohne Kalender-Event ist kein Befund.
        result.missingInCalendar = result.unpairedCandidates
            .filter { relevantStatuses.contains($0.status) }
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

    /// Auftritte, für die ein Kalendereintrag erwartet wird («Fehlt im Kalender»):
    /// Datum bestätigt, aber noch nicht abgeschlossen. `requested` erwartet noch keinen
    /// Eintrag (wird aber gepaart, falls einer existiert), `cancelled` ist raus,
    /// `completed/invoiced/closed` sind erledigte Vorgänge ohne Kalender-Anspruch.
    private static let relevantStatuses: Set<KeynoteStatus> = [
        .dateConfirmedFeeOffered, .feeConfirmed, .contentAgreed, .contractSigned
    ]

    // MARK: - Stiller Abgleich (Auto-Link / Auto-Abbruch)

    /// Auftritte, die der stille Abgleich abbrechen darf, wenn ihr Kalendereintrag
    /// verschwunden ist: alle mit Kalender-Anspruch plus `requested` — ein angefragter
    /// Auftritt, der einmal verknüpft war, verliert mit dem Event seine Grundlage.
    /// Erledigte Vorgänge (`completed`/`invoiced`/`closed`) bleiben unangetastet.
    static let autoCancelStatuses: Set<KeynoteStatus> = relevantStatuses.union([.requested])

    /// Mindestalter einer Verknüpfung, bevor ihr Fehlen als Löschung gilt — schützt
    /// vor der CloudKit-Race, bei der ein Auftritt vor seinem iCloud-Kalender-Event
    /// auf ein Zweitgerät synct.
    static let autoCancelGrace: TimeInterval = 24 * 3600

    struct CalendarSyncActions {
        var toLink: [ReconciliationResult.MatchedPair] = []
        var toCancel: [Keynote] = []

        var isEmpty: Bool { toLink.isEmpty && toCancel.isEmpty }
    }

    /// Entscheidet, was der stille Hintergrund-Abgleich tun darf.
    ///
    /// - `toLink`: exakte Zeit-Matches mit fehlender oder abweichender ID werden neu
    ///   verknüpft — repariert Legacy-Einträge und instabile Cross-Device-IDs, bevor
    ///   über einen Abbruch entschieden wird. Tages-Matches (`timeMismatch`) bleiben
    ///   Nutzer-Entscheid im Abgleich-Sheet, sind aber gepaart und damit nie
    ///   Abbruch-Kandidaten.
    /// - `toCancel`: nur Auftritte, die einmal verknüpft waren (`calendarEventID`),
    ///   deren Verknüpfung älter als die Grace-Period ist und deren Status in
    ///   `autoCancelStatuses` liegt. Fail-safe: ohne `calendarLinkedAt` kein Abbruch.
    /// - Safety-Valve: eine leere Event-Liste (leerer, falscher oder noch nicht
    ///   gesyncter Kalender) löst nie Aktionen aus.
    static func syncActions(
        keynotes: [Keynote],
        events: [ReconciliationEvent],
        now: Date = .now
    ) -> CalendarSyncActions {
        guard !events.isEmpty else { return CalendarSyncActions() }

        let result = reconcile(keynotes: keynotes, events: events, now: now)
        var actions = CalendarSyncActions()
        actions.toLink = result.matching.filter(\.needsLink)
        actions.toCancel = result.unpairedCandidates.filter { keynote in
            keynote.calendarEventID != nil &&
            autoCancelStatuses.contains(keynote.status) &&
            keynote.calendarLinkedAt.map { now.timeIntervalSince($0) > autoCancelGrace } ?? false
        }
        return actions
    }

    /// Bricht einen Auftritt ab, dessen Kalendereintrag entfernt wurde: Status auf
    /// «Abgebrochen», Transparenz-Notiz in den Notizen, Verknüpfung gelöscht — eine
    /// stale ID würde sonst das grüne Kalender-Badge zeigen und die Neuanlage eines
    /// Termins blockieren.
    static func applyCancel(to keynote: Keynote, at date: Date = .now) {
        keynote.status = .cancelled
        let stamp = date.formatted(
            Date.FormatStyle(
                date: .numeric,
                time: .shortened,
                locale: Locale(identifier: "de_CH"),
                calendar: .home,
                timeZone: .home
            )
        )
        let note = "Automatisch abgebrochen am \(stamp) — Kalendereintrag wurde entfernt."
        keynote.notes = keynote.notes.isEmpty ? note : keynote.notes + "\n\n" + note
        keynote.calendarEventID = nil
        keynote.calendarLinkedAt = nil
    }

    // MARK: - Übernahme (Gruppe 1)

    /// Erstellt aus einem Kalender-Event einen neuen Auftritt.
    /// Hinweis: Bei mehreren übernommenen Occurrences desselben Serien-Events
    /// erhalten alle Auftritte dieselbe `calendarEventID` (EventKit vergibt pro Serie nur eine).
    static func makeKeynote(
        from event: ReconciliationEvent,
        status: KeynoteStatus = .dateConfirmedFeeOffered
    ) -> Keynote {
        let title = displayTitle(for: event)
        let minutes = max(event.end.timeIntervalSince(event.start) / 60, 15)
        return Keynote(
            eventName: title,
            eventDate: event.start,
            keynoteTitle: title,
            duration: minutes,
            location: event.location ?? "",
            status: status,
            calendarEventID: event.eventIdentifier,
            calendarLinkedAt: .now,
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

    // MARK: - Serientermine

    /// Event-Identifier, die im Abgleichszeitraum mehrfach vorkommen — also Occurrences
    /// eines Serientermins sind. EventKit vergibt pro Serie nur eine ID; Update/Löschen
    /// über die ID trifft die ganze Serie und muss dafür gesperrt werden.
    static func recurringIdentifiers(in events: [ReconciliationEvent]) -> Set<String> {
        var counts: [String: Int] = [:]
        for event in events {
            counts[event.eventIdentifier, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }
}

// MARK: - Timeline-Zeilen

/// Eine Zeile der Abgleichs-Zeitachse: alle vier Ergebnisgruppen chronologisch verschränkt,
/// damit App (links) und Kalender (rechts) direkt gegenübergestellt werden können.
enum TimelineRow: Identifiable {
    case matched(ReconciliationResult.MatchedPair)
    case timeMismatch(ReconciliationResult.MatchedPair)
    case calendarOnly(ReconciliationEvent)
    case appOnly(Keynote)

    var id: String {
        switch self {
        case .matched(let pair): "matched|\(pair.id)"
        case .timeMismatch(let pair): "mismatch|\(pair.id)"
        case .calendarOnly(let event): "calendar|\(event.id)"
        case .appOnly(let keynote): "app|\(String(describing: keynote.persistentModelID))"
        }
    }

    /// Massgebliches Datum für die Einordnung auf der Achse;
    /// bei abweichender Zeit das frühere der beiden Daten.
    var sortDate: Date {
        switch self {
        case .matched(let pair): pair.keynote.eventDate
        case .timeMismatch(let pair): min(pair.keynote.eventDate, pair.event.start)
        case .calendarOnly(let event): event.start
        case .appOnly(let keynote): keynote.eventDate
        }
    }
}

/// Zeilen eines Monats, für die Monats-Marker entlang der Achse.
struct TimelineSection: Identifiable {
    let monthStart: Date
    let rows: [TimelineRow]

    var id: Date { monthStart }
}

extension ReconciliationResult {
    /// Alle vier Gruppen als eine chronologisch sortierte Zeilenliste;
    /// Tie-Break über die ID, damit die Reihenfolge deterministisch bleibt.
    var timelineRows: [TimelineRow] {
        let rows: [TimelineRow] =
            matching.map(TimelineRow.matched) +
            timeMismatch.map(TimelineRow.timeMismatch) +
            onlyInCalendar.map(TimelineRow.calendarOnly) +
            missingInCalendar.map(TimelineRow.appOnly)
        return rows.sorted { ($0.sortDate, $0.id) < ($1.sortDate, $1.id) }
    }

    /// Zeilen gruppiert nach Monat in der Heimatzeitzone.
    func timelineSections(calendar: Calendar = .home) -> [TimelineSection] {
        var sections: [TimelineSection] = []
        var currentMonth: Date?
        var currentRows: [TimelineRow] = []

        for row in timelineRows {
            let month = calendar.dateInterval(of: .month, for: row.sortDate)?.start ?? row.sortDate
            if month != currentMonth {
                if let currentMonth {
                    sections.append(TimelineSection(monthStart: currentMonth, rows: currentRows))
                }
                currentMonth = month
                currentRows = []
            }
            currentRows.append(row)
        }
        if let currentMonth {
            sections.append(TimelineSection(monthStart: currentMonth, rows: currentRows))
        }
        return sections
    }
}
