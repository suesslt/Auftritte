//
//  SettingsView.swift
//  Auftritte
//
//  App-Einstellungen (aktuell: Kilometerpreis für den Report «Steuerabzüge Fahrten»).
//

import SwiftUI
import EventKit

// MARK: - App Settings

enum AppSettings {
    static let kilometerpreisKey = "settings.kilometerpreisCHF"
    static let kilometerpreisDefault: Double = 0.70

    /// Aktueller Kilometerpreis in CHF als Decimal (für Geld-Berechnungen).
    static var kilometerpreis: Decimal {
        let stored = UserDefaults.standard.object(forKey: kilometerpreisKey) as? Double
        return Decimal(stored ?? kilometerpreisDefault)
    }

    static let kalenderIDKey = "settings.abgleichKalenderID"

    /// calendarIdentifier des Zielkalenders; nil = Standardkalender.
    /// Leerer String gilt als «nicht konfiguriert», weil @AppStorage keinen String? unterstützt.
    static var kalenderID: String? {
        let stored = UserDefaults.standard.string(forKey: kalenderIDKey)
        return (stored?.isEmpty ?? true) ? nil : stored
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.kilometerpreisKey)
    private var kilometerpreis: Double = AppSettings.kilometerpreisDefault
    @AppStorage(AppSettings.kalenderIDKey)
    private var kalenderID: String = ""
    @EnvironmentObject private var calendarService: CalendarService

    var body: some View {
        NavigationStack {
            Form {
                Section("Kalender") {
                    kalenderAuswahl
                }
                Section("Fahrtkosten") {
                    HStack {
                        Text("Kilometerpreis")
                        Spacer()
                        TextField("Preis", value: $kilometerpreis, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("CHF/km")
                    }
                    Text("Für den Report «Steuerabzüge Fahrten»: Kosten = 2 × Distanz × Kilometerpreis (Hin- und Rückfahrt).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    // MARK: - Kalender-Auswahl

    @ViewBuilder
    private var kalenderAuswahl: some View {
        switch calendarService.authorizationStatus {
        case .fullAccess:
            Picker("Kalender für Auftritte", selection: $kalenderID) {
                Text("Standardkalender").tag("")
                ForEach(calendarService.writableCalendars(), id: \.calendarIdentifier) { calendar in
                    Text(calendar.title).tag(calendar.calendarIdentifier)
                }
            }
            Text("Wird für Save-the-Date-Einträge und den Abgleich mit dem Kalender verwendet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .notDetermined:
            Button("Kalenderzugriff erlauben") {
                Task { _ = await calendarService.requestAccess() }
            }
        default:
            Text("Kalenderzugriff verweigert. Bitte in den Systemeinstellungen erlauben.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Systemeinstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(CalendarService())
}
