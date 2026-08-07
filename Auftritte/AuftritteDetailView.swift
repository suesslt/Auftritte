//
//  KeynoteDetailView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//
//  Detailansicht eines Auftritts, nach Frageperspektive gegliedert:
//  Termin (Wann/Wo + Kalender-Verknüpfung) → Auftritt (Was) →
//  Auftraggeber (Für wen) → Honorar (Konditionen) → Status & Pendenz → Notizen.
//

import Score
import ScoreUI
import SwiftUI
import SwiftData
import EventKit

struct KeynoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var keynote: Keynote
    @EnvironmentObject private var calendarService: CalendarService
    @StateObject private var contactsService = ContactsService()
    @StateObject private var errorHandler = ErrorHandler()

    @State private var showingContactPicker = false
    @State private var showingStatusChange = false
    @State private var showingFixDateSheet = false
    @State private var showingUnlinkConfirmation = false
    @State private var showingNotesEditor = false
    @State private var availabilityEvents: [String] = []
    @State private var isCheckingAvailability = false
    @State private var didCheckAvailability = false

    var isNewKeynote: Bool
    var onCancel: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil

    var body: some View {
        Form {
            terminSection
            auftrittSection
            auftraggeberSection
            honorarSection
            statusPendenzSection
            notesSection
        }
        .navigationTitle(isNewKeynote ? "Neuer Auftritt" : keynote.eventName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isNewKeynote {
                    Button("Abbrechen") {
                        onCancel?()
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isNewKeynote {
                    Button("Sichern") {
                        saveNewKeynote()
                    }
                    .disabled(keynote.eventName.isEmpty || keynote.keynoteTitle.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingStatusChange) {
            StatusChangeView(keynote: keynote, calendarService: calendarService)
        }
        .sheet(isPresented: $showingContactPicker) {
            ContactPickerView(
                contactsService: contactsService,
                onContactSelected: { identifier in
                    contactsService.applyContact(from: identifier, to: keynote)
                }
            )
        }
        .sheet(isPresented: $showingFixDateSheet) {
            FixDateSheet(keynote: keynote)
                .environmentObject(calendarService)
        }
        .fullScreenCover(isPresented: $showingNotesEditor) {
            NotesEditorView(keynote: keynote)
        }
        .confirmationDialog(
            "Kalendereintrag löschen und Datum zurücksetzen?",
            isPresented: $showingUnlinkConfirmation,
            titleVisibility: .visible
        ) {
            Button("Kalendereintrag löschen", role: .destructive) {
                unlinkAndReset()
            }
            Button("Behalten", role: .cancel) { }
        } message: {
            Text("Der Auftritt gilt danach als «Datum noch nicht geklärt» und der Eintrag wird aus dem Kalender entfernt.")
        }
        .errorAlert(errorHandler: errorHandler)
    }

    // MARK: - Termin

    private var terminSection: some View {
        Section("Termin") {
            if keynote.status == .cancelled {
                Label("Auftritt abgebrochen", systemImage: "calendar.badge.minus")
                    .foregroundStyle(.red)
                Button {
                    keynote.status = .requested
                    showingFixDateSheet = true
                } label: {
                    Label("Reaktivieren & neuen Termin anlegen", systemImage: "arrow.counterclockwise")
                }
            }

            Toggle("Datum bekannt", isOn: datumBekanntBinding)

            if keynote.inAbklaerung {
                Text("Ohne fixes Datum gibt es keinen Kalendereintrag. Beim Einschalten wird der Termin im Kalender eingetragen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                DatePicker("Datum", selection: $keynote.eventDate, displayedComponents: .date)
                DatePicker("Zeit", selection: $keynote.eventDate, displayedComponents: .hourAndMinute)

                HStack {
                    Text("Redezeit")
                    Spacer()
                    TextField("Minuten", value: $keynote.duration, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("Min.")
                }

                TextField("Ort", text: $keynote.location)

                if keynote.status != .cancelled {
                    if keynote.calendarEventID != nil {
                        Label("Kalender-Eintrag vorhanden", systemImage: "calendar.badge.checkmark")
                            .foregroundStyle(.green)
                    } else {
                        Label("Kein Kalendereintrag", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Button("Kalendereintrag erstellen") {
                            createCalendarEvent()
                        }
                    }

                    availabilityRows
                }
            }
        }
    }

    /// Kalender-first: das Datum gilt erst als bekannt, wenn der Termin im Kalender
    /// steht. Einschalten ohne Verknüpfung öffnet darum das Termin-Sheet (der Toggle
    /// flippt erst nach erfolgreichem Eintrag); Ausschalten mit Verknüpfung verlangt
    /// eine Bestätigung, weil der Kalendereintrag dabei gelöscht wird.
    private var datumBekanntBinding: Binding<Bool> {
        Binding(
            get: { !keynote.inAbklaerung },
            set: { datumBekannt in
                if datumBekannt {
                    if keynote.calendarEventID == nil {
                        showingFixDateSheet = true
                    } else {
                        keynote.inAbklaerung = false
                    }
                } else {
                    if keynote.calendarEventID != nil {
                        showingUnlinkConfirmation = true
                    } else {
                        keynote.inAbklaerung = true
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var availabilityRows: some View {
        Button(action: checkAvailability) {
            HStack {
                Label("Verfügbarkeit prüfen", systemImage: "calendar.badge.clock")
                if isCheckingAvailability {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isCheckingAvailability)

        if !availabilityEvents.isEmpty {
            ForEach(availabilityEvents, id: \.self) { event in
                Label(event, systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        } else if didCheckAvailability && !isCheckingAvailability {
            Label("Keine Konflikte gefunden", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        }
    }

    // MARK: - Auftritt

    private var auftrittSection: some View {
        Section("Auftritt") {
            TextField("Name des Anlasses", text: $keynote.eventName)

            TextField("Titel der Keynote", text: $keynote.keynoteTitle)

            TextField("Thema", text: $keynote.keynoteTheme)

            TextField("Sprache", text: $keynote.language)

            TextField("Zielpublikum", text: $keynote.targetAudience)

            HStack {
                Text("Anzahl Zuhörer")
                Spacer()
                TextField("Anzahl", value: $keynote.attendeeCount, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        }
    }

    // MARK: - Auftraggeber & Kontakt

    private var auftraggeberSection: some View {
        Section("Auftraggeber & Kontakt") {
            TextField("Firma/Organisation", text: $keynote.clientOrganization)

            TextField("Vorname", text: $keynote.contactFirstName)
                .textContentType(.givenName)

            TextField("Name", text: $keynote.contactLastName)
                .textContentType(.familyName)

            TextField("E-Mail", text: $keynote.contactEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Telefon", text: $keynote.contactPhone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)

            Button {
                showingContactPicker = true
            } label: {
                Label(
                    keynote.contactHasData ? "Aus Kontakten übernehmen" : "Aus Kontakten wählen",
                    systemImage: "person.crop.circle.badge.plus"
                )
            }
        }
    }

    // MARK: - Honorar & Fahrt

    private var honorarSection: some View {
        Section("Honorar & Fahrt") {
            HStack {
                Text("Honorar")
                Spacer()
                TextField("Betrag", value: $keynote.agreedFee, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                Text("CHF")
            }

            HStack {
                Text("Distanz")
                Spacer()
                TextField("km", value: $keynote.distanceKm, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("km")
            }

            DatePicker("Anfragedatum", selection: $keynote.requestDate, displayedComponents: .date)
        }
    }

    // MARK: - Status & Pendenz

    private var statusPendenzSection: some View {
        Section("Status & Pendenz") {
            HStack {
                Circle()
                    .fill(keynote.status.color)
                    .frame(width: 12, height: 12)
                Text(keynote.status.rawValue)
                Spacer()
                if !keynote.status.nextStatus.isEmpty {
                    Button("Status ändern") {
                        showingStatusChange = true
                    }
                }
            }

            Picker("Pendenz", selection: $keynote.pendenz) {
                ForEach(Pendenz.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            TextField("Pendenz-Notiz", text: $keynote.pendenzNote, axis: .vertical)
                .lineLimit(1...4)

            Toggle("Erledigt", isOn: $keynote.pendenzErledigt)
        }
    }

    // MARK: - Notizen

    private var notesSection: some View {
        Section("Notizen") {
            TextEditor(text: $keynote.notes)
                .frame(minHeight: 220)

            Button {
                showingNotesEditor = true
            } label: {
                Label("Im Vollbild bearbeiten", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }
    }

    // MARK: - Aktionen

    private func saveNewKeynote() {
        modelContext.insert(keynote)
        onSave?()
    }

    private func createCalendarEvent() {
        Task {
            do {
                guard let eventID = try await calendarService.createSaveTheDate(for: keynote) else {
                    throw CalendarError.accessDenied
                }
                keynote.calendarEventID = eventID
                keynote.calendarLinkedAt = .now
            } catch {
                errorHandler.handle(error, title: "Kalendereintrag konnte nicht erstellt werden")
            }
        }
    }

    /// Datum zurück auf «noch nicht geklärt»: Verknüpfung lösen und den
    /// Kalendereintrag entfernen (ein bereits gelöschter Eintrag ist kein Fehler).
    private func unlinkAndReset() {
        let eventID = keynote.calendarEventID
        keynote.calendarEventID = nil
        keynote.calendarLinkedAt = nil
        keynote.inAbklaerung = true
        guard let eventID else { return }
        Task {
            do {
                try await calendarService.deleteEvent(eventID: eventID)
            } catch CalendarError.eventNotFound {
                // Eintrag war schon weg — genau der Zustand, den wir wollen.
            } catch {
                errorHandler.handle(error, title: "Kalendereintrag konnte nicht gelöscht werden")
            }
        }
    }

    private func checkAvailability() {
        isCheckingAvailability = true
        availabilityEvents = []

        Task {
            let hasAccess = await calendarService.requestAccess()

            guard hasAccess else {
                isCheckingAvailability = false
                return
            }

            let events = calendarService.checkAvailability(
                for: keynote.eventDate,
                duration: keynote.duration,
                excludingEventID: keynote.calendarEventID
            )

            availabilityEvents = events.map { event in
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.timeZone = .home
                let timeString = formatter.string(from: event.startDate)
                return "\(timeString): \(event.title ?? "Unbekannt")"
            }

            didCheckAvailability = true
            isCheckingAvailability = false
        }
    }
}

// MARK: - Termin-Sheet (FixDateSheet)

/// Einziger Commit-Punkt vom ungeklärten zum fixen Datum: Bestätigen schreibt
/// Datum/Redezeit/Ort auf den Auftritt, erstellt den Kalendereintrag und hebt
/// «in Abklärung» auf. Abbrechen lässt alles unverändert (der Toggle springt zurück).
private struct FixDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calendarService: CalendarService
    @StateObject private var errorHandler = ErrorHandler()

    @Bindable var keynote: Keynote

    @State private var date: Date
    @State private var duration: Double
    @State private var location: String
    @State private var isCreating = false

    init(keynote: Keynote) {
        self.keynote = keynote
        _date = State(initialValue: max(keynote.eventDate, .now))
        _duration = State(initialValue: keynote.duration)
        _location = State(initialValue: keynote.location)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Termin") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    DatePicker("Zeit", selection: $date, displayedComponents: .hourAndMinute)
                    HStack {
                        Text("Redezeit")
                        Spacer()
                        TextField("Minuten", value: $duration, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("Min.")
                    }
                    TextField("Ort", text: $location)
                }

                Section {
                    Button {
                        commit()
                    } label: {
                        if isCreating {
                            HStack {
                                ProgressView()
                                Text("Wird eingetragen…")
                            }
                        } else {
                            Label("Termin im Kalender eintragen", systemImage: "calendar.badge.plus")
                        }
                    }
                    .disabled(isCreating)
                } footer: {
                    Text("Erstellt den Kalendereintrag und fixiert damit das Datum des Auftritts.")
                }
            }
            .navigationTitle("Termin festlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .errorAlert(errorHandler: errorHandler)
    }

    private func commit() {
        isCreating = true
        Task {
            defer { isCreating = false }
            keynote.eventDate = date
            keynote.duration = duration
            keynote.location = location
            do {
                guard let eventID = try await calendarService.createSaveTheDate(for: keynote) else {
                    throw CalendarError.accessDenied
                }
                keynote.calendarEventID = eventID
                keynote.calendarLinkedAt = .now
                keynote.inAbklaerung = false
                dismiss()
            } catch {
                errorHandler.handle(error, title: "Termin konnte nicht erstellt werden")
            }
        }
    }
}

// MARK: - Vollbild-Notiz-Editor

private struct NotesEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var keynote: Keynote
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $keynote.notes)
                .focused($isFocused)
                .padding(.horizontal)
                .navigationTitle(keynote.eventName.isEmpty ? "Notizen" : "Notizen — \(keynote.eventName)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        // Direkt-Bindung wie im restlichen Formular — «Fertig» schliesst nur.
                        Button("Fertig") { dismiss() }
                    }
                }
                .onAppear { isFocused = true }
        }
    }
}

// MARK: - Status Change View

struct StatusChangeView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var keynote: Keynote
    var calendarService: CalendarService
    @StateObject private var errorHandler = ErrorHandler()

    @State private var selectedStatus: KeynoteStatus?
    @State private var showingSaveCalendarOption = false

    var body: some View {
        NavigationStack {
            List {
                Section("Mögliche nächste Status") {
                    ForEach(keynote.status.nextStatus) { status in
                        Button(action: {
                            selectedStatus = status
                            if status == .dateConfirmedFeeOffered && keynote.calendarEventID == nil {
                                showingSaveCalendarOption = true
                            } else {
                                updateStatus(to: status, createCalendarEvent: false)
                            }
                        }) {
                            HStack {
                                Circle()
                                    .fill(status.color)
                                    .frame(width: 12, height: 12)
                                Text(status.rawValue)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Status ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
            .alert("Save the Date erstellen?", isPresented: $showingSaveCalendarOption) {
                Button("Ja", role: .none) {
                    if let status = selectedStatus {
                        updateStatus(to: status, createCalendarEvent: true)
                    }
                }
                Button("Nein", role: .cancel) {
                    if let status = selectedStatus {
                        updateStatus(to: status, createCalendarEvent: false)
                    }
                }
            } message: {
                Text("Möchtest du einen 'Save the Date' Eintrag im Kalender erstellen?")
            }
            .errorAlert(errorHandler: errorHandler)
        }
    }

    private func updateStatus(to status: KeynoteStatus, createCalendarEvent: Bool) {
        keynote.status = status

        guard createCalendarEvent else {
            dismiss()
            return
        }
        // Erst nach erfolgreichem Kalendereintrag schliessen — sonst würde der
        // Fehler-Alert mit dem Sheet verschwinden.
        Task {
            do {
                if let eventID = try await calendarService.createSaveTheDate(for: keynote) {
                    keynote.calendarEventID = eventID
                    keynote.calendarLinkedAt = .now
                }
                dismiss()
            } catch {
                errorHandler.handle(error, title: "Kalendereintrag konnte nicht erstellt werden")
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        KeynoteDetailView(keynote: Keynote(), isNewKeynote: true)
    }
    .modelContainer(for: Keynote.self, inMemory: true)
    .environmentObject(CalendarService())
}
