//
//  CalendarAutoSync.swift
//  Auftritte
//
//  Stiller Hintergrund-Abgleich: der Kalender ist die Quelle der Wahrheit.
//  Läuft einmal beim Start und bei jeder Kalender-Änderung (EKEventStoreChanged);
//  verknüpft exakte Zeit-Matches neu und bricht Auftritte ab, deren Kalendereintrag
//  entfernt wurde (Entscheidung: `ReconciliationEngine.syncActions`).
//
//  Schreibt ausschliesslich SwiftData, nie in den Kalender — es entsteht also
//  keine Rückkopplung über EKEventStoreChanged.
//

import Score
import Foundation
import Combine
import EventKit
import SwiftData

@MainActor
final class CalendarAutoSync: ObservableObject {

    private var observerTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var isRunning = false

    /// Initial-Lauf plus Beobachtung von Kalender-Änderungen mit 2-s-Debounce.
    /// Idempotent — ein zweiter Aufruf startet keine zweite Beobachtung.
    func start(context: ModelContext, calendarService: CalendarService) {
        runOnce(context: context, calendarService: calendarService)

        guard observerTask == nil else { return }
        observerTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged).map({ _ in () }) {
                guard let self else { return }
                self.debounceTask?.cancel()
                self.debounceTask = Task { [weak self] in
                    guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
                    self?.runOnce(context: context, calendarService: calendarService)
                }
            }
        }
    }

    private func runOnce(context: ModelContext, calendarService: CalendarService) {
        // Ohne Vollzugriff oder ohne bewusst konfigurierten Kalender still überspringen —
        // gegen den falschen Kalender zu prüfen wäre schlimmer als gar nicht zu prüfen.
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              calendarService.configuredCalendar != nil,
              !isRunning
        else { return }
        isRunning = true
        defer { isRunning = false }

        guard let keynotes = try? context.fetch(FetchDescriptor<Keynote>()) else { return }

        let now = Date.now
        let horizon = Calendar.home.date(byAdding: .year, value: ReconciliationEngine.horizonYears, to: now) ?? now
        let events = calendarService.fetchSyncEvents(from: now, to: horizon)

        let actions = ReconciliationEngine.syncActions(keynotes: keynotes, events: events, now: now)
        guard !actions.isEmpty else { return }

        for pair in actions.toLink {
            pair.keynote.calendarEventID = pair.event.eventIdentifier
            pair.keynote.calendarLinkedAt = now
        }
        for keynote in actions.toCancel {
            ReconciliationEngine.applyCancel(to: keynote, at: now)
        }
        try? context.save()
    }
}
