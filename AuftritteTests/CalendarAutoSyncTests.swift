//
//  CalendarAutoSyncTests.swift
//  AuftritteTests
//
//  Tests für die Entscheidungslogik des stillen Kalender-Abgleichs:
//  wann wird still neu verknüpft (`toLink`), wann automatisch abgebrochen
//  (`toCancel`) — und vor allem: wann sicher NICHT abgebrochen.
//

import Score
import Testing
import Foundation
@testable import Auftritte

struct CalendarAutoSyncTests {

    private static let homeCalendar = Calendar.home

    // Fixe Referenzzeit: 01.09.2026, 08:00 Heimatzeit.
    private let now = Self.homeCalendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 8))!

    private func date(day: Int, month: Int = 10, year: Int = 2026, hour: Int = 14, minute: Int = 0) -> Date {
        Self.homeCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Verknüpfung, deren Grace-Period abgelaufen ist (48 h vor `now`).
    private var staleLink: Date { now.addingTimeInterval(-48 * 3600) }
    /// Frische Verknüpfung innerhalb der Grace-Period (1 h vor `now`).
    private var freshLink: Date { now.addingTimeInterval(-3600) }

    private func makeKeynote(
        title: String = "Führung im Wandel",
        eventDate: Date,
        status: KeynoteStatus = .feeConfirmed,
        calendarEventID: String? = nil,
        calendarLinkedAt: Date? = nil,
        inAbklaerung: Bool = false,
        notes: String = ""
    ) -> Keynote {
        Keynote(
            eventName: "GV Beispiel AG",
            eventDate: eventDate,
            keynoteTitle: title,
            status: status,
            calendarEventID: calendarEventID,
            calendarLinkedAt: calendarLinkedAt,
            notes: notes,
            inAbklaerung: inAbklaerung
        )
    }

    private func makeEvent(
        id: String = "event-1",
        title: String = "Führung im Wandel",
        start: Date,
        durationMinutes: Double = 60
    ) -> ReconciliationEvent {
        ReconciliationEvent(
            eventIdentifier: id,
            title: title,
            start: start,
            end: start.addingTimeInterval(durationMinutes * 60),
            timeZone: nil,
            location: nil,
            notes: nil
        )
    }

    /// Event an einem anderen Tag als alle Test-Auftritte — erfüllt das
    /// Safety-Valve (Event-Liste nicht leer), ohne ein Paar zu bilden.
    private var unrelatedEvent: ReconciliationEvent {
        makeEvent(id: "unrelated", title: "Anderer Auftritt", start: date(day: 28))
    }

    // MARK: - Abbruch

    @Test func staleLinkedKeynote_eventGone_isCancelled() {
        let keynote = makeKeynote(eventDate: date(day: 10), calendarEventID: "geloescht", calendarLinkedAt: staleLink)

        let actions = ReconciliationEngine.syncActions(keynotes: [keynote], events: [unrelatedEvent], now: now)

        #expect(actions.toCancel.count == 1)
        #expect(actions.toLink.isEmpty)
    }

    @Test func requestedStatus_withStaleLink_isCancelled() {
        let keynote = makeKeynote(
            eventDate: date(day: 10),
            status: .requested,
            calendarEventID: "geloescht",
            calendarLinkedAt: staleLink
        )

        let actions = ReconciliationEngine.syncActions(keynotes: [keynote], events: [unrelatedEvent], now: now)

        #expect(actions.toCancel.count == 1)
    }

    // MARK: - Kein Abbruch (Schutzmechanismen)

    @Test func exactTimeMatchWithDifferentID_isRelinkedNotCancelled() {
        // Cross-Device-Fall: die gespeicherte ID stammt vom anderen Gerät und löst
        // lokal nicht auf — der Zeit-Match rettet den Auftritt und verknüpft neu.
        let start = date(day: 10)
        let keynote = makeKeynote(eventDate: start, calendarEventID: "id-vom-anderen-geraet", calendarLinkedAt: staleLink)
        let event = makeEvent(id: "lokale-id", start: start)

        let actions = ReconciliationEngine.syncActions(keynotes: [keynote], events: [event], now: now)

        #expect(actions.toCancel.isEmpty)
        #expect(actions.toLink.count == 1)
        #expect(actions.toLink.first?.event.eventIdentifier == "lokale-id")
    }

    @Test func sameDayFuzzyMatch_neitherLinkedNorCancelled() {
        // Tages-Match mit abweichender Zeit bleibt Nutzer-Entscheid im Abgleich-Sheet,
        // schützt aber vor dem Auto-Abbruch.
        let keynote = makeKeynote(eventDate: date(day: 10, hour: 14), calendarEventID: "alt", calendarLinkedAt: staleLink)
        let event = makeEvent(id: "neu", start: date(day: 10, hour: 17, minute: 30))

        let actions = ReconciliationEngine.syncActions(keynotes: [keynote], events: [event], now: now)

        #expect(actions.toCancel.isEmpty)
        #expect(actions.toLink.isEmpty)
    }

    @Test func freshLink_withinGrace_isNotCancelled() {
        let keynote = makeKeynote(eventDate: date(day: 10), calendarEventID: "geloescht", calendarLinkedAt: freshLink)

        let actions = ReconciliationEngine.syncActions(keynotes: [keynote], events: [unrelatedEvent], now: now)

        #expect(actions.toCancel.isEmpty)
    }

    @Test func neverLinkedKeynote_isNotCancelled() {
        let keynote = makeKeynote(eventDate: date(day: 10), calendarEventID: nil)

        let actions = ReconciliationEngine.syncActions(keynotes: [keynote], events: [unrelatedEvent], now: now)

        #expect(actions.toCancel.isEmpty)
    }

    @Test func linkedWithoutStamp_failSafe_isNotCancelled() {
        // ID vorhanden, aber kein Grace-Anker (sollte nach der Migration nicht
        // vorkommen) — im Zweifel nie abbrechen.
        let keynote = makeKeynote(eventDate: date(day: 10), calendarEventID: "geloescht", calendarLinkedAt: nil)

        let actions = ReconciliationEngine.syncActions(keynotes: [keynote], events: [unrelatedEvent], now: now)

        #expect(actions.toCancel.isEmpty)
    }

    @Test func inAbklaerung_isNeverCancelled_evenWithStaleLink() {
        let keynote = makeKeynote(
            eventDate: date(day: 10),
            calendarEventID: "geloescht",
            calendarLinkedAt: staleLink,
            inAbklaerung: true
        )

        let actions = ReconciliationEngine.syncActions(keynotes: [keynote], events: [unrelatedEvent], now: now)

        #expect(actions.toCancel.isEmpty)
    }

    @Test func terminalAndCompletedStatuses_areNeverCancelled() {
        let statuses: [KeynoteStatus] = [.completed, .invoiced, .closed, .cancelled]
        let keynotes = statuses.map {
            makeKeynote(eventDate: date(day: 10), status: $0, calendarEventID: "geloescht", calendarLinkedAt: staleLink)
        }

        let actions = ReconciliationEngine.syncActions(keynotes: keynotes, events: [unrelatedEvent], now: now)

        #expect(actions.toCancel.isEmpty)
    }

    @Test func pastEvent_andBeyondHorizon_areNotCancelled() {
        let past = makeKeynote(eventDate: date(day: 15, month: 8), calendarEventID: "geloescht", calendarLinkedAt: staleLink)
        let farFuture = makeKeynote(eventDate: date(day: 15, year: 2029), calendarEventID: "geloescht", calendarLinkedAt: staleLink)

        let actions = ReconciliationEngine.syncActions(keynotes: [past, farFuture], events: [unrelatedEvent], now: now)

        #expect(actions.toCancel.isEmpty)
    }

    @Test func emptyEventList_safetyValve_noActions() {
        // Leerer, falscher oder noch nicht gesyncter Kalender darf nie zu
        // Massen-Abbruch führen.
        let keynote = makeKeynote(eventDate: date(day: 10), calendarEventID: "geloescht", calendarLinkedAt: staleLink)

        let actions = ReconciliationEngine.syncActions(keynotes: [keynote], events: [], now: now)

        #expect(actions.isEmpty)
    }

    @Test func matchingWithStoredID_isNotRelinked() {
        let start = date(day: 10)
        let keynote = makeKeynote(eventDate: start, calendarEventID: "event-1", calendarLinkedAt: staleLink)
        let event = makeEvent(id: "event-1", start: start)

        let actions = ReconciliationEngine.syncActions(keynotes: [keynote], events: [event], now: now)

        #expect(actions.isEmpty)
    }

    // MARK: - unpairedCandidates

    @Test func unpairedCandidates_isSupersetOfMissingInCalendar_includingRequested() {
        let requested = makeKeynote(eventDate: date(day: 10), status: .requested)
        let confirmed = makeKeynote(eventDate: date(day: 12), status: .feeConfirmed)

        let result = ReconciliationEngine.reconcile(keynotes: [requested, confirmed], events: [unrelatedEvent], now: now)

        #expect(result.unpairedCandidates.count == 2)
        #expect(result.missingInCalendar.count == 1)
        #expect(result.missingInCalendar.first?.status == .feeConfirmed)
    }

    // MARK: - applyCancel

    @Test func applyCancel_setsStatus_appendsNote_clearsLink() {
        let keynote = makeKeynote(
            eventDate: date(day: 10),
            calendarEventID: "geloescht",
            calendarLinkedAt: staleLink,
            notes: "Briefing-Call erledigt."
        )

        ReconciliationEngine.applyCancel(to: keynote, at: date(day: 10, hour: 6, minute: 30))

        #expect(keynote.status == .cancelled)
        #expect(keynote.calendarEventID == nil)
        #expect(keynote.calendarLinkedAt == nil)
        #expect(keynote.notes.hasPrefix("Briefing-Call erledigt.\n\n"))
        #expect(keynote.notes.contains("Automatisch abgebrochen am 10.10.2026"))
        #expect(keynote.notes.contains("Kalendereintrag wurde entfernt."))
    }

    @Test func applyCancel_onEmptyNotes_writesNoteWithoutLeadingBlankLines() {
        let keynote = makeKeynote(eventDate: date(day: 10), calendarEventID: "geloescht", calendarLinkedAt: staleLink)

        ReconciliationEngine.applyCancel(to: keynote, at: date(day: 10, hour: 6, minute: 30))

        #expect(keynote.notes.hasPrefix("Automatisch abgebrochen am"))
    }
}
