//
//  CalendarReconciliationTests.swift
//  AuftritteTests
//

import Score
import Testing
import Foundation
@testable import Auftritte

struct CalendarReconciliationTests {

    // Alle Testdaten werden in der Heimatzeitzone (Europe/Zurich) gebaut, damit die
    // Tests unabhängig von der Zeitzone der Maschine deterministisch sind — die Engine
    // vergleicht Tage ebenfalls in der Event- bzw. Heimatzeitzone.
    private static let homeCalendar = Calendar.home

    // Fixe Referenzzeit: 01.09.2026, 08:00 Heimatzeit.
    private let now = Self.homeCalendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 8))!

    private func date(day: Int, month: Int = 10, year: Int = 2026, hour: Int = 14, minute: Int = 0) -> Date {
        Self.homeCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeKeynote(
        title: String = "Führung im Wandel",
        eventName: String = "GV Beispiel AG",
        eventDate: Date,
        status: KeynoteStatus = .feeConfirmed,
        calendarEventID: String? = nil,
        inAbklaerung: Bool = false
    ) -> Keynote {
        Keynote(
            eventName: eventName,
            eventDate: eventDate,
            keynoteTitle: title,
            status: status,
            calendarEventID: calendarEventID,
            inAbklaerung: inAbklaerung
        )
    }

    private func makeEvent(
        id: String = "event-1",
        title: String = "Führung im Wandel",
        start: Date,
        durationMinutes: Double = 60,
        timeZone: TimeZone? = nil
    ) -> ReconciliationEvent {
        ReconciliationEvent(
            eventIdentifier: id,
            title: title,
            start: start,
            end: start.addingTimeInterval(durationMinutes * 60),
            timeZone: timeZone,
            location: nil,
            notes: nil
        )
    }

    // MARK: - Zeit-Match

    @Test func sameStartTime_isMatching_andLinksMissingID() {
        let start = date(day: 10)
        let keynote = makeKeynote(eventDate: start)
        let event = makeEvent(id: "event-1", start: start)

        let result = ReconciliationEngine.reconcile(keynotes: [keynote], events: [event], now: now)

        #expect(result.matching.count == 1)
        #expect(result.matching.first?.needsLink == true)
        #expect(result.timeMismatch.isEmpty)
        #expect(result.onlyInCalendar.isEmpty)
        #expect(result.missingInCalendar.isEmpty)
    }

    @Test func sameStartTime_storedIDMatches_noRelink() {
        let start = date(day: 10)
        let keynote = makeKeynote(eventDate: start, calendarEventID: "event-1")
        let event = makeEvent(id: "event-1", start: start)

        let result = ReconciliationEngine.reconcile(keynotes: [keynote], events: [event], now: now)

        #expect(result.matching.count == 1)
        #expect(result.matching.first?.needsLink == false)
    }

    @Test func staleEventID_matchesByTimeAnyway_andRelinks() {
        // IDs sind nicht geräteübergreifend stabil — der Match läuft rein über die Zeit,
        // eine abweichende gespeicherte ID wird beim Übernehmen neu verknüpft.
        let start = date(day: 10)
        let keynote = makeKeynote(eventDate: start, calendarEventID: "id-vom-anderen-geraet")
        let event = makeEvent(id: "lokale-id", title: "Zahnarzttermin", start: start)

        let result = ReconciliationEngine.reconcile(keynotes: [keynote], events: [event], now: now)

        #expect(result.matching.count == 1)
        #expect(result.matching.first?.needsLink == true)
        #expect(result.matching.first?.event.eventIdentifier == "lokale-id")
    }

    @Test func shiftedStartTime_isTimeMismatch() {
        let keynote = makeKeynote(eventDate: date(day: 10, hour: 14))
        let event = makeEvent(start: date(day: 10, hour: 14, minute: 30))

        let result = ReconciliationEngine.reconcile(keynotes: [keynote], events: [event], now: now)

        #expect(result.timeMismatch.count == 1)
        #expect(result.matching.isEmpty)
    }

    @Test func midnightKeynote_pairsWithEveningEventSameDay() {
        // Realfall «Urbane Frauen Schweiz»: Auftritt in der App auf Mitternacht des
        // Tages, Event im Kalender am selben Tag um 17:30 → dasselbe Paar,
        // ausgewiesen als Zeitabweichung.
        let keynote = makeKeynote(eventDate: date(day: 11, hour: 0))
        let event = makeEvent(start: date(day: 11, hour: 17, minute: 30))

        let result = ReconciliationEngine.reconcile(keynotes: [keynote], events: [event], now: now)

        #expect(result.timeMismatch.count == 1)
        #expect(result.onlyInCalendar.isEmpty)
        #expect(result.missingInCalendar.isEmpty)
    }

    @Test func dayComparison_usesEventTimeZone_notDeviceTimeZone() {
        // Auftritt 00:30 und Event 23:00 desselben Zürcher Tages: in Europe/Zurich
        // derselbe Tag, in weiter westlichen Zeitzonen nicht. Massgeblich ist die
        // Zeitzone des Events, also muss das Paar unabhängig von der Gerätezeitzone entstehen.
        let zurich = TimeZone(identifier: "Europe/Zurich")!
        var zurichCalendar = Calendar(identifier: .gregorian)
        zurichCalendar.timeZone = zurich
        let keynoteStart = zurichCalendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 0, minute: 30))!
        let eventStart = zurichCalendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 23))!

        let keynote = makeKeynote(eventDate: keynoteStart)
        let event = makeEvent(start: eventStart, timeZone: zurich)

        let result = ReconciliationEngine.reconcile(keynotes: [keynote], events: [event], now: now)

        #expect(result.timeMismatch.count == 1)
        #expect(result.missingInCalendar.isEmpty)
        #expect(result.onlyInCalendar.isEmpty)
    }

    @Test func exactMatch_pairsEvenAcrossMidnight() {
        // Startzeitpunkte unter einer Minute auseinander gelten immer als übereinstimmend,
        // auch wenn sie knapp auf verschiedene Kalendertage fallen.
        let keynote = makeKeynote(eventDate: date(day: 10, hour: 23, minute: 59).addingTimeInterval(50))
        let event = makeEvent(start: date(day: 11, hour: 0, minute: 0))

        let result = ReconciliationEngine.reconcile(keynotes: [keynote], events: [event], now: now)

        #expect(result.matching.count == 1)
    }

    @Test func oneDayApart_noPairing() {
        let keynote = makeKeynote(eventDate: date(day: 10))
        let event = makeEvent(start: date(day: 11))

        let result = ReconciliationEngine.reconcile(keynotes: [keynote], events: [event], now: now)

        #expect(result.onlyInCalendar.count == 1)
        #expect(result.missingInCalendar.count == 1)
        #expect(result.matching.isEmpty)
        #expect(result.timeMismatch.isEmpty)
    }

    @Test func greedyPairing_nearestDistanceWins() {
        // Ein Event um 15:00 liegt zwischen zwei Auftritten (14:00, 15:00) —
        // es gehört zum zeitlich näheren Auftritt, der andere fehlt im Kalender.
        let keynoteA = makeKeynote(title: "A", eventDate: date(day: 10, hour: 14))
        let keynoteB = makeKeynote(title: "B", eventDate: date(day: 10, hour: 15))
        let event = makeEvent(start: date(day: 10, hour: 15))

        let result = ReconciliationEngine.reconcile(keynotes: [keynoteA, keynoteB], events: [event], now: now)

        #expect(result.matching.count == 1)
        #expect(result.matching.first?.keynote.keynoteTitle == "B")
        #expect(result.missingInCalendar.count == 1)
        #expect(result.missingInCalendar.first?.keynoteTitle == "A")
    }

    @Test func twoPairs_matchIndependently() {
        let keynoteA = makeKeynote(title: "A", eventDate: date(day: 10, hour: 14))
        let keynoteB = makeKeynote(title: "B", eventDate: date(day: 10, hour: 18))
        let events = [
            makeEvent(id: "e-1", start: date(day: 10, hour: 14)),
            makeEvent(id: "e-2", start: date(day: 10, hour: 18, minute: 30)),
        ]

        let result = ReconciliationEngine.reconcile(keynotes: [keynoteA, keynoteB], events: events, now: now)

        #expect(result.matching.count == 1)
        #expect(result.matching.first?.keynote.keynoteTitle == "A")
        #expect(result.timeMismatch.count == 1)
        #expect(result.timeMismatch.first?.keynote.keynoteTitle == "B")
    }

    @Test func titlesAreIrrelevantForPairing() {
        // Der Zielkalender enthält ausschliesslich Auftritte — der Titel spielt keine Rolle.
        let start = date(day: 10)
        let keynote = makeKeynote(title: "Führung im Wandel", eventName: "GV Beispiel AG", eventDate: start)
        let event = makeEvent(title: "Irgendein anderer Titel", start: start)

        let result = ReconciliationEngine.reconcile(keynotes: [keynote], events: [event], now: now)

        #expect(result.matching.count == 1)
    }

    // MARK: - Keynote-Filter

    @Test func filter_excludesIrrelevantKeynotes() {
        let start = date(day: 10)
        let excluded = [
            makeKeynote(eventDate: start, status: .requested),
            makeKeynote(eventDate: start, status: .cancelled),
            makeKeynote(eventDate: start, status: .closed),
            makeKeynote(eventDate: start, inAbklaerung: true),
            makeKeynote(eventDate: date(day: 10, month: 8)),           // Vergangenheit
            makeKeynote(eventDate: date(day: 10, year: 2029)),         // > 2 Jahre voraus
        ]

        let result = ReconciliationEngine.reconcile(keynotes: excluded, events: [], now: now)

        #expect(result.isEmpty)
    }

    @Test func unmatchedEvent_isOnlyInCalendar() {
        let event = makeEvent(start: date(day: 10))

        let result = ReconciliationEngine.reconcile(keynotes: [], events: [event], now: now)

        #expect(result.onlyInCalendar.count == 1)
    }

    // MARK: - makeKeynote

    @Test func makeKeynote_stripsPrefixAndMapsFields() {
        let start = date(day: 10)
        let event = ReconciliationEvent(
            eventIdentifier: "event-1",
            title: "SAVE THE DATE: Führung im Wandel",
            start: start,
            end: start.addingTimeInterval(90 * 60),
            timeZone: nil,
            location: "Luzern",
            notes: "Notiz"
        )

        let keynote = ReconciliationEngine.makeKeynote(from: event)

        #expect(keynote.keynoteTitle == "Führung im Wandel")
        #expect(keynote.eventName == "Führung im Wandel")
        #expect(keynote.eventDate == start)
        #expect(keynote.duration == 90)
        #expect(keynote.location == "Luzern")
        #expect(keynote.notes == "Notiz")
        #expect(keynote.status == .dateConfirmedFeeOffered)
        #expect(keynote.calendarEventID == "event-1")
    }

    @Test func makeKeynote_zeroDuration_fallsBackToMinimum() {
        let start = date(day: 10)
        let event = makeEvent(start: start, durationMinutes: 0)

        let keynote = ReconciliationEngine.makeKeynote(from: event)

        #expect(keynote.duration == 15)
    }

    // MARK: - Wiederkehrende Events

    @Test func recurring_matchesOccurrenceByTime_otherStaysInCalendarGroup() {
        let firstOccurrence = date(day: 10)
        let secondOccurrence = date(day: 17)
        let keynote = makeKeynote(eventDate: secondOccurrence)
        let events = [
            makeEvent(id: "serie-1", start: firstOccurrence),
            makeEvent(id: "serie-1", start: secondOccurrence),
        ]

        let result = ReconciliationEngine.reconcile(keynotes: [keynote], events: events, now: now)

        #expect(result.matching.count == 1)
        #expect(result.matching.first?.event.start == secondOccurrence)
        #expect(result.onlyInCalendar.count == 1)
        #expect(result.onlyInCalendar.first?.start == firstOccurrence)
    }

    @Test func occurrenceIDs_areUniquePerOccurrence() {
        let a = makeEvent(id: "serie-1", start: date(day: 10))
        let b = makeEvent(id: "serie-1", start: date(day: 17))
        #expect(a.id != b.id)
    }
}
