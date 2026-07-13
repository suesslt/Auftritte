//
//  SettingsView.swift
//  Auftritte
//
//  App-Einstellungen (aktuell: Kilometerpreis für den Report «Steuerabzüge Fahrten»).
//

import SwiftUI

// MARK: - App Settings

enum AppSettings {
    static let kilometerpreisKey = "settings.kilometerpreisCHF"
    static let kilometerpreisDefault: Double = 0.70

    /// Aktueller Kilometerpreis in CHF als Decimal (für Geld-Berechnungen).
    static var kilometerpreis: Decimal {
        let stored = UserDefaults.standard.object(forKey: kilometerpreisKey) as? Double
        return Decimal(stored ?? kilometerpreisDefault)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.kilometerpreisKey)
    private var kilometerpreis: Double = AppSettings.kilometerpreisDefault

    var body: some View {
        NavigationStack {
            Form {
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
}

#Preview {
    SettingsView()
}
