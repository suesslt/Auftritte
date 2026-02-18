//
//  CalendarService.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import Foundation
import EventKit
import Combine

@MainActor
class CalendarService: ObservableObject {
    private let eventStore = EKEventStore()
    @Published var authorizationStatus: EKAuthorizationStatus
    
    init() {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            print("Fehler beim Anfordern des Kalenderzugriffs: \(error)")
            return false
        }
    }
    
    func createSaveTheDate(for keynote: Keynote) async throws -> String? {
        if authorizationStatus != .fullAccess {
            let granted = await requestAccess()
            guard granted else { return nil }
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = "SAVE THE DATE: \(keynote.keynoteTitle)"
        event.startDate = keynote.eventDate
        event.endDate = keynote.eventDate.addingTimeInterval(keynote.duration * 60)
        event.location = keynote.location
        event.notes = """
        Anlass: \(keynote.eventName)
        Thema: \(keynote.keynoteTheme)
        Auftraggeber: \(keynote.clientOrganization)
        Honorar: \(keynote.agreedFee) CHF
        """
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        try eventStore.save(event, span: .thisEvent)
        
        return event.eventIdentifier
    }
    
    func updateEvent(eventID: String, for keynote: Keynote) async throws {
        guard let event = eventStore.event(withIdentifier: eventID) else {
            throw CalendarError.eventNotFound
        }
        
        event.title = "SAVE THE DATE: \(keynote.keynoteTitle)"
        event.startDate = keynote.eventDate
        event.endDate = keynote.eventDate.addingTimeInterval(keynote.duration * 60)
        event.location = keynote.location
        event.notes = """
        Anlass: \(keynote.eventName)
        Thema: \(keynote.keynoteTheme)
        Auftraggeber: \(keynote.clientOrganization)
        Honorar: \(keynote.agreedFee) CHF
        """
        
        try eventStore.save(event, span: .thisEvent)
    }
    
    func deleteEvent(eventID: String) async throws {
        guard let event = eventStore.event(withIdentifier: eventID) else {
            throw CalendarError.eventNotFound
        }
        
        try eventStore.remove(event, span: .thisEvent)
    }
    
    func checkAvailability(for date: Date, duration: TimeInterval, excludingEventID: String? = nil) -> [EKEvent] {
        let startDate = Calendar.current.startOfDay(for: date)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        // Filtere das aktuelle Event aus, falls vorhanden
        return events.filter { event in
            if let excludingID = excludingEventID, event.eventIdentifier == excludingID {
                return false
            }
            return true
        }
    }
}

enum CalendarError: LocalizedError {
    case eventNotFound
    case accessDenied
    
    var errorDescription: String? {
        switch self {
        case .eventNotFound:
            return "Kalender-Event nicht gefunden"
        case .accessDenied:
            return "Zugriff auf Kalender verweigert"
        }
    }
}
