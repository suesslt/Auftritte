//
//  CalendarReconciliationView.swift
//  Auftritte
//
//  Sheet für «Abgleich mit Kalender»: stellt Auftritte (links) und Kalender-Events
//  (rechts) auf einer vertikalen Zeitachse einander gegenüber. Jede Zeile ist direkt
//  aktionsfähig: importieren, verknüpfen, Zeiten angleichen, Event erstellen.
//

import Score
import ScoreUI
import SwiftUI
import SwiftData
import EventKit

struct CalendarReconciliationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var calendarService: CalendarService

    @State private var phase: Phase = .loading
    @State private var showingSettings = false
    /// TimelineRow.id der Zeile, deren Aktion gerade läuft — serialisiert EventKit-Aufrufe.
    @State private var busyRowID: String?
    @State private var mismatchDialogPair: ReconciliationResult.MatchedPair?
    /// Event-IDs von Serienterminen: Update/Verknüpfen gesperrt, da EventKit
    /// pro Serie nur eine ID vergibt und Änderungen die ganze Serie treffen.
    @State private var seriesIDs: Set<String> = []
    @StateObject private var errorHandler = ErrorHandler()

    private enum Phase {
        case loading
        case accessDenied
        case noCalendarConfigured
        case result(ReconciliationResult)
        case failed(message: String)
    }

    private let axisWidth: CGFloat = 36
    private let connectorWidth: CGFloat = 12

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
                case .failed(let message):
                    failedView(message: message)
                }
            }
            .navigationTitle("Abgleich mit Kalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .errorAlert(errorHandler: errorHandler)
        .task { await load() }
        .sheet(isPresented: $showingSettings, onDismiss: {
            phase = .loading
            Task { await load() }
        }) {
            SettingsView()
                .environmentObject(calendarService)
        }
        .confirmationDialog(
            "Zeit angleichen",
            isPresented: mismatchDialogPresented,
            titleVisibility: .visible,
            presenting: mismatchDialogPair
        ) { pair in
            Button("Zeit aus Kalender übernehmen (\(timeLabel(pair.event.start)))") {
                adoptCalendarTime(pair)
            }
            if !seriesIDs.contains(pair.event.eventIdentifier) {
                Button("Zeit in Kalender übertragen (\(timeLabel(pair.keynote.eventDate)))") {
                    pushTimeToCalendar(pair)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { pair in
            if seriesIDs.contains(pair.event.eventIdentifier) {
                Text("\(rowTitle(for: pair.keynote)) — Serientermin, Änderungen am Kalender bitte direkt im Kalender vornehmen.")
            } else {
                Text(rowTitle(for: pair.keynote))
            }
        }
    }

    private var mismatchDialogPresented: Binding<Bool> {
        Binding(
            get: { mismatchDialogPair != nil },
            set: { if !$0 { mismatchDialogPair = nil } }
        )
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
        await reload()
    }

    /// Fetch + Reconcile ohne Zugriffs-/Konfigurations-Checks; nach Aktionen wird ohne
    /// `.loading`-Phase neu geladen, damit die Timeline nicht vollflächig flackert.
    private func reload() async {
        let now = Date()
        let horizon = Calendar.home.date(byAdding: .year, value: ReconciliationEngine.horizonYears, to: now) ?? now
        let events = calendarService.fetchReconciliationEvents(from: now, to: horizon)
            .filter { !$0.isAllDay }   // Ganztages-Events: kein sinnvoller Startzeit-Vergleich
            .map(ReconciliationEvent.init)

        do {
            let keynotes = try modelContext.fetch(FetchDescriptor<Keynote>())
            let result = ReconciliationEngine.reconcile(keynotes: keynotes, events: events, now: now)
            seriesIDs = ReconciliationEngine.recurringIdentifiers(in: events)
            phase = .result(result)
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Aktionen

    /// Führt eine Zeilen-Aktion aus: Zeile als beschäftigt markieren, Fehler in den
    /// ErrorHandler leiten, danach neu abgleichen.
    private func perform(rowID: String, _ work: @escaping () async throws -> Void) {
        guard busyRowID == nil else { return }
        busyRowID = rowID
        Task { @MainActor in
            do {
                try await work()
            } catch {
                errorHandler.handle(error, title: "Abgleich fehlgeschlagen")
            }
            await reload()
            busyRowID = nil
        }
    }

    private func importEvent(_ event: ReconciliationEvent, rowID: String) {
        perform(rowID: rowID) {
            modelContext.insert(ReconciliationEngine.makeKeynote(from: event))
            try modelContext.save()
        }
    }

    private func createCalendarEvent(for keynote: Keynote, rowID: String) {
        perform(rowID: rowID) {
            guard let eventID = try await calendarService.createSaveTheDate(for: keynote) else {
                throw CalendarError.accessDenied
            }
            keynote.calendarEventID = eventID
            keynote.calendarLinkedAt = .now
            try modelContext.save()
        }
    }

    private func adoptCalendarTime(_ pair: ReconciliationResult.MatchedPair) {
        perform(rowID: "mismatch|\(pair.id)") {
            pair.keynote.eventDate = pair.event.start
            // Serientermine teilen eine Event-ID — nicht verknüpfen, sonst würde
            // Löschen/Ändern eines Auftritts die ganze Serie treffen.
            if !seriesIDs.contains(pair.event.eventIdentifier) {
                pair.keynote.calendarEventID = pair.event.eventIdentifier
                pair.keynote.calendarLinkedAt = .now
            }
            try modelContext.save()
        }
    }

    private func pushTimeToCalendar(_ pair: ReconciliationResult.MatchedPair) {
        perform(rowID: "mismatch|\(pair.id)") {
            pair.keynote.calendarEventID = pair.event.eventIdentifier
            pair.keynote.calendarLinkedAt = .now
            try await calendarService.updateEvent(eventID: pair.event.eventIdentifier, for: pair.keynote)
            try modelContext.save()
        }
    }

    private func link(_ pair: ReconciliationResult.MatchedPair, rowID: String) {
        perform(rowID: rowID) {
            pair.keynote.calendarEventID = pair.event.eventIdentifier
            pair.keynote.calendarLinkedAt = .now
            try modelContext.save()
        }
    }

    private func linkAll(_ result: ReconciliationResult) {
        perform(rowID: "linkAll") {
            for pair in result.timeMismatch + result.matching
            where pair.needsLink && !seriesIDs.contains(pair.event.eventIdentifier) {
                pair.keynote.calendarEventID = pair.event.eventIdentifier
                pair.keynote.calendarLinkedAt = .now
            }
            try modelContext.save()
        }
    }

    private func linkableCount(_ result: ReconciliationResult) -> Int {
        (result.timeMismatch + result.matching)
            .filter { $0.needsLink && !seriesIDs.contains($0.event.eventIdentifier) }
            .count
    }

    // MARK: - Result-Phase

    private func resultView(result: ReconciliationResult) -> some View {
        VStack(spacing: 0) {
            summaryBanner(result: result)

            if result.isEmpty {
                emptyState
            } else {
                timeline(result: result)
            }

            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Button {
                        linkAll(result)
                    } label: {
                        Label("Alle verknüpfen (\(linkableCount(result)))", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(linkableCount(result) == 0 || busyRowID != nil)
                }
                .padding()
            }
        }
    }

    // MARK: - Timeline

    private func timeline(result: ReconciliationResult) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                columnHeader
                ForEach(result.timelineSections()) { section in
                    monthMarker(section.monthStart)
                    ForEach(section.rows) { row in
                        timelineRow(row)
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Auftritte")
                .frame(maxWidth: .infinity)
            Spacer()
                .frame(width: axisWidth + 2 * connectorWidth)
            Text("Kalender")
                .frame(maxWidth: .infinity)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.top, 12)
        .padding(.horizontal, 12)
    }

    /// Monats-Marker: Capsule auf der Achsenlinie. Links/rechts gleiche flexible
    /// Breiten wie die Zeilen, daher liegt die Linie exakt in der Mitte.
    private func monthMarker(_ monthStart: Date) -> some View {
        ZStack {
            axisLine
            Text(monthTitle(monthStart))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .overlay(Capsule().strokeBorder(Color(.systemGray4)))
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
    }

    private func monthTitle(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: .home).month(.wide).year())
    }

    @ViewBuilder
    private func timelineRow(_ row: TimelineRow) -> some View {
        switch row {
        case .matched(let pair):
            pairRow(rowID: row.id, pair: pair, mismatch: false)
        case .timeMismatch(let pair):
            pairRow(rowID: row.id, pair: pair, mismatch: true)
        case .calendarOnly(let event):
            calendarOnlyRow(rowID: row.id, event: event)
        case .appOnly(let keynote):
            appOnlyRow(rowID: row.id, keynote: keynote)
        }
    }

    private func pairRow(rowID: String, pair: ReconciliationResult.MatchedPair, mismatch: Bool) -> some View {
        let accent: Color = mismatch ? .orange : .green
        let isSeries = seriesIDs.contains(pair.event.eventIdentifier)
        return HStack(alignment: .center, spacing: 0) {
            TimelineCard(
                title: rowTitle(for: pair.keynote),
                date: pair.keynote.eventDate,
                location: pair.keynote.location,
                accent: accent,
                timeHighlighted: mismatch,
                actionTitle: mismatch ? "Zeit angleichen…" : nil,
                action: mismatch ? { mismatchDialogPair = pair } : nil,
                isBusy: busyRowID == rowID,
                actionsDisabled: busyRowID != nil
            )
            connector(accent)
            axisColumn(color: accent)
            connector(accent)
            TimelineCard(
                title: ReconciliationEngine.displayTitle(for: pair.event),
                date: pair.event.start,
                location: pair.event.location,
                accent: accent,
                timeHighlighted: mismatch,
                badge: (pair.needsLink && isSeries)
                    ? "Serientermin — bitte im Kalender bearbeiten" : nil,
                actionTitle: (!mismatch && pair.needsLink && !isSeries) ? "Verknüpfen" : nil,
                action: (!mismatch && pair.needsLink && !isSeries)
                    ? { link(pair, rowID: rowID) } : nil,
                isBusy: !mismatch && busyRowID == rowID,
                actionsDisabled: busyRowID != nil
            )
        }
        .padding(.horizontal, 12)
    }

    private func calendarOnlyRow(rowID: String, event: ReconciliationEvent) -> some View {
        HStack(alignment: .center, spacing: 0) {
            TimelineGapCard(
                text: "Fehlt in der App",
                accent: .blue,
                actionTitle: "Als Auftritt übernehmen",
                action: { importEvent(event, rowID: rowID) },
                isBusy: busyRowID == rowID,
                actionsDisabled: busyRowID != nil
            )
            connector(.blue, dashed: true)
            axisColumn(color: .blue)
            connector(.blue)
            TimelineCard(
                title: ReconciliationEngine.displayTitle(for: event),
                date: event.start,
                location: event.location,
                accent: .blue
            )
        }
        .padding(.horizontal, 12)
    }

    private func appOnlyRow(rowID: String, keynote: Keynote) -> some View {
        HStack(alignment: .center, spacing: 0) {
            TimelineCard(
                title: rowTitle(for: keynote),
                date: keynote.eventDate,
                location: keynote.location,
                accent: .red
            )
            connector(.red)
            axisColumn(color: .red)
            connector(.red, dashed: true)
            TimelineGapCard(
                text: "Fehlt im Kalender",
                accent: .red,
                actionTitle: "Im Kalender eintragen",
                action: { createCalendarEvent(for: keynote, rowID: rowID) },
                isBusy: busyRowID == rowID,
                actionsDisabled: busyRowID != nil
            )
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Achse

    private var axisLine: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(width: 2)
    }

    /// Achsensegment einer Zeile: durchgehende Linie (Zeilenabstand 0!) plus farbiger Knoten.
    private func axisColumn(color: Color) -> some View {
        ZStack {
            axisLine
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
        }
        .frame(width: axisWidth)
    }

    private func connector(_ color: Color, dashed: Bool = false) -> some View {
        Group {
            if dashed {
                HorizontalLine()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [3]))
                    .foregroundStyle(Color(.systemGray3))
            } else {
                Rectangle()
                    .fill(color.opacity(0.5))
                    .frame(height: 2)
            }
        }
        .frame(width: connectorWidth)
    }

    private func rowTitle(for keynote: Keynote) -> String {
        !keynote.keynoteTitle.isEmpty ? keynote.keynoteTitle :
        !keynote.eventName.isEmpty ? keynote.eventName : "Ohne Titel"
    }

    private func timeLabel(_ date: Date) -> String {
        date.homeFormatted(date: .omitted, time: .shortened)
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

// MARK: - Karten

/// Karte für einen Auftritt oder ein Kalender-Event: Titel, Startzeitpunkt,
/// optional Ort, Hinweis und Aktion.
private struct TimelineCard: View {
    let title: String
    let date: Date
    let location: String?
    let accent: Color
    var timeHighlighted = false
    var badge: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var isBusy = false
    var actionsDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 4) {
                if timeHighlighted {
                    Image(systemName: "clock.badge.exclamationmark")
                }
                Text(date.homeFormatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption)
            .foregroundStyle(timeHighlighted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            if let location, !location.isEmpty {
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let badge {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
                    .tint(accent)
                    .disabled(actionsDisabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.35)))
        .padding(.vertical, 6)
    }
}

/// Platzhalter für die fehlende Seite eines Eintrags, mit der passenden Aktion.
private struct TimelineGapCard: View {
    let text: String
    let accent: Color
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var isBusy = false
    var actionsDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
                    .tint(accent)
                    .disabled(actionsDisabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(.systemGray3), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
        .padding(.vertical, 6)
    }
}

/// Horizontale Linie für gestrichelte Verbindungsstücke.
private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Preview

#Preview {
    CalendarReconciliationView(calendarService: CalendarService())
        .modelContainer(for: [Keynote.self], inMemory: true)
}
