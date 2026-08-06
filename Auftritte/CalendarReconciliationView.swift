//
//  CalendarReconciliationView.swift
//  Auftritte
//
//  Sheet für «Abgleich mit Kalender»: vergleicht den konfigurierten Apple-Kalender
//  mit den Auftritten und zeigt vier Gruppen. Aufbau analog CSVImportView.
//

import Score
import SwiftUI
import SwiftData
import EventKit

struct CalendarReconciliationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var calendarService: CalendarService

    @State private var phase: Phase = .loading
    @State private var selectedEventIDs: Set<String> = []   // ReconciliationEvent.id
    @State private var showingSettings = false

    private enum Phase {
        case loading
        case accessDenied
        case noCalendarConfigured
        case result(ReconciliationResult)
        case applying
        case done(imported: Int, linked: Int)
        case failed(message: String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    loadingView
                case .accessDenied:
                    accessDeniedView
                case .noCalendarConfigured:
                    noCalendarView
                case .result(let result):
                    resultView(result: result)
                case .applying:
                    applyingView
                case .done(let imported, let linked):
                    doneView(imported: imported, linked: linked)
                case .failed(let message):
                    failedView(message: message)
                }
            }
            .navigationTitle("Abgleich mit Kalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingSettings, onDismiss: {
            phase = .loading
            Task { await load() }
        }) {
            SettingsView()
        }
    }

    // MARK: - Laden & Abgleich

    private func load() async {
        if calendarService.authorizationStatus != .fullAccess {
            let granted = await calendarService.requestAccess()
            guard granted else {
                phase = .accessDenied
                return
            }
        }
        guard AppSettings.kalenderID != nil else {
            phase = .noCalendarConfigured
            return
        }

        let now = Date()
        let horizon = Calendar.home.date(byAdding: .year, value: ReconciliationEngine.horizonYears, to: now) ?? now
        let events = calendarService.fetchReconciliationEvents(from: now, to: horizon)
            .filter { !$0.isAllDay }   // Ganztages-Events: kein sinnvoller Startzeit-Vergleich
            .map(ReconciliationEvent.init)

        do {
            let keynotes = try modelContext.fetch(FetchDescriptor<Keynote>())
            let result = ReconciliationEngine.reconcile(keynotes: keynotes, events: events, now: now)
            selectedEventIDs = Set(result.onlyInCalendar.map(\.id))
            phase = .result(result)
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Übernehmen

    private func apply(result: ReconciliationResult) {
        phase = .applying

        Task { @MainActor in
            do {
                var imported = 0
                for event in result.onlyInCalendar where selectedEventIDs.contains(event.id) {
                    modelContext.insert(ReconciliationEngine.makeKeynote(from: event))
                    imported += 1
                }

                var linked = 0
                for pair in result.timeMismatch + result.matching where pair.needsLink {
                    pair.keynote.calendarEventID = pair.event.eventIdentifier
                    linked += 1
                }

                try modelContext.save()
                phase = .done(imported: imported, linked: linked)
            } catch {
                phase = .failed(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Result-Phase

    private func resultView(result: ReconciliationResult) -> some View {
        VStack(spacing: 0) {
            summaryBanner(result: result)

            if result.isEmpty {
                emptyState
            } else {
                resultList(result: result)
            }

            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button("Alle auswählen") {
                        selectedEventIDs = Set(result.onlyInCalendar.map(\.id))
                    }
                    .font(.subheadline)
                    .disabled(result.onlyInCalendar.isEmpty)

                    Spacer()

                    Button {
                        apply(result: result)
                    } label: {
                        Label("Übernehmen (\(selectedEventIDs.count))", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedEventIDs.isEmpty && result.pendingLinkCount == 0)
                }
                .padding()
            }
        }
    }

    private func resultList(result: ReconciliationResult) -> some View {
        List(selection: $selectedEventIDs) {
            if !result.onlyInCalendar.isEmpty {
                Section {
                    ForEach(result.onlyInCalendar) { event in
                        calendarOnlyRow(event: event)
                            .tag(event.id)
                    }
                } header: {
                    Text("Nur im Kalender (\(result.onlyInCalendar.count))")
                } footer: {
                    Text("Ausgewählte Einträge werden als neue Auftritte übernommen.")
                }
            }

            if !result.timeMismatch.isEmpty {
                Section {
                    ForEach(result.timeMismatch) { pair in
                        timeMismatchRow(pair: pair)
                            .selectionDisabled()
                    }
                } header: {
                    Text("Zeit weicht ab (\(result.timeMismatch.count))")
                } footer: {
                    Text("Bitte manuell in App oder Kalender korrigieren.")
                }
            }

            if !result.missingInCalendar.isEmpty {
                Section {
                    ForEach(result.missingInCalendar, id: \.persistentModelID) { keynote in
                        missingRow(keynote: keynote)
                            .selectionDisabled()
                    }
                } header: {
                    Text("Fehlt im Kalender (\(result.missingInCalendar.count))")
                } footer: {
                    Text("Bitte manuell in App oder Kalender korrigieren.")
                }
            }

            if !result.matching.isEmpty {
                Section {
                    ForEach(result.matching) { pair in
                        matchingRow(pair: pair)
                            .selectionDisabled()
                    }
                } header: {
                    Text("Übereinstimmend (\(result.matching.count))")
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Zeilen

    private func calendarOnlyRow(event: ReconciliationEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ReconciliationEngine.displayTitle(for: event))
                .font(.body)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(event.start.homeFormatted(date: .abbreviated, time: .shortened))
                if let location = event.location, !location.isEmpty {
                    Text("·")
                    Text(location)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func timeMismatchRow(pair: ReconciliationResult.MatchedPair) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(rowTitle(for: pair.keynote))
                    .font(.body)
                    .lineLimit(1)
                Text("App: \(pair.keynote.eventDate.homeFormatted(date: .abbreviated, time: .shortened)) · Kalender: \(pair.event.start.homeFormatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func missingRow(keynote: Keynote) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(rowTitle(for: keynote))
                    .font(.body)
                    .lineLimit(1)
                Text(keynote.eventDate.homeFormatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func matchingRow(pair: ReconciliationResult.MatchedPair) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(rowTitle(for: pair.keynote))
                    .font(.body)
                    .lineLimit(1)
                Text(pair.keynote.eventDate.homeFormatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if pair.needsLink {
                Text("wird verknüpft")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                    .foregroundStyle(.blue)
            }
        }
    }

    private func rowTitle(for keynote: Keynote) -> String {
        !keynote.keynoteTitle.isEmpty ? keynote.keynoteTitle :
        !keynote.eventName.isEmpty ? keynote.eventName : "Ohne Titel"
    }

    // MARK: - Summary Banner

    private func summaryBanner(result: ReconciliationResult) -> some View {
        HStack(spacing: 16) {
            summaryChip(count: result.onlyInCalendar.count, label: "Neu", color: .blue, icon: "calendar.badge.plus")
            summaryChip(count: result.timeMismatch.count, label: "Zeit", color: .orange, icon: "clock.badge.exclamationmark")
            summaryChip(count: result.missingInCalendar.count, label: "Fehlt", color: .red, icon: "calendar.badge.exclamationmark")
            summaryChip(count: result.matching.count, label: "OK", color: .green, icon: "checkmark.circle.fill")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private func summaryChip(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sonstige Phasen

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Keine zukünftigen Auftritte oder Kalendereinträge im Abgleichszeitraum.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Kalender wird abgeglichen…")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var applyingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Änderungen werden übernommen…")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var accessDeniedView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 72))
                .foregroundStyle(.orange)
            VStack(spacing: 8) {
                Text("Kein Kalenderzugriff")
                    .font(.title2.bold())
                Text("Kalenderzugriff verweigert. Bitte in den Systemeinstellungen erlauben.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Systemeinstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var noCalendarView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Kein Kalender ausgewählt")
                    .font(.title2.bold())
                Text("Bitte wähle in den Einstellungen den Kalender für den Abgleich.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Einstellungen öffnen") {
                showingSettings = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func doneView(imported: Int, linked: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("Abgleich abgeschlossen")
                    .font(.title2.bold())
                Text("\(imported) Auftritt\(imported == 1 ? "" : "e") importiert, \(linked) verknüpft.")
                    .foregroundStyle(.secondary)
            }
            Button("Fertig") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)
            VStack(spacing: 8) {
                Text("Abgleich fehlgeschlagen")
                    .font(.title2.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Erneut versuchen") {
                phase = .loading
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    CalendarReconciliationView(calendarService: CalendarService())
        .modelContainer(for: [Keynote.self], inMemory: true)
}
