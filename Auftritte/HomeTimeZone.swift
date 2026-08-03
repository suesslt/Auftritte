//
//  HomeTimeZone.swift
//  Auftritte
//
//  Heimatzeitzone der Auftritte. Alle Termine werden als absolute Zeitpunkte
//  gespeichert, aber immer in dieser Zeitzone angezeigt, eingegeben und
//  formatiert — unabhängig davon, in welcher Zeitzone das Gerät gerade steht.
//  Ohne diese Verankerung würde ein Auftritt um 17:30 auf Reisen (z.B. GMT+4)
//  als 19:30 erscheinen und ein Mitternachts-Datum auf den Folgetag rutschen.
//

import Foundation

extension TimeZone {
    /// Heimatzeitzone, in der alle Auftritte stattfinden und angezeigt werden.
    static let home = TimeZone(identifier: "Europe/Zurich")!
}

extension Calendar {
    /// Gregorianischer Kalender in der Heimatzeitzone — für alle Tages-, Monats-
    /// und Jahresberechnungen rund um Auftrittsdaten.
    static let home: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .home
        return calendar
    }()
}

extension Date {
    /// Wie `formatted(date:time:)`, aber fix in der Heimatzeitzone statt der Gerätezeitzone.
    func homeFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time, timeZone: .home))
    }
}
