//
//  KeynoteDetailView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import SwiftUI
import SwiftData
import EventKit

struct KeynoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Bindable var keynote: Keynote
    @StateObject private var calendarService = CalendarService()
    @StateObject private var contactsService = ContactsService()
    
    @State private var showingContactPicker = false
    @State private var showingStatusChange = false
    @State private var showingSaveCalendarAlert = false
    @State private var availabilityEvents: [String] = []
    @State private var isCheckingAvailability = false
    
    var isNewKeynote: Bool
    var onCancel: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    
    var body: some View {
        Form {
            basicInfoSection
            dateTimeSection
            detailsSection
            contactSection
            pendenzSection
            statusSection
            availabilitySection
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
        .alert("Save the Date erstellt", isPresented: $showingSaveCalendarAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Ein Kalender-Eintrag wurde erfolgreich erstellt.")
        }
    }
    
    private var basicInfoSection: some View {
        Section("Grundinformationen") {
            TextField("Name des Anlasses", text: $keynote.eventName)

            TextField("Titel der Keynote", text: $keynote.keynoteTitle)
            
            TextField("Thema", text: $keynote.keynoteTheme)
            
            HStack {
                Text("Redezeit")
                Spacer()
                TextField("Minuten", value: $keynote.duration, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("Min.")
            }
            
            TextField("Sprache", text: $keynote.language)
        }
    }

    private var dateTimeSection: some View {
        Section("Datum und Zeit") {
            Toggle("Datum bekannt", isOn: Binding(
                get: { !keynote.inAbklaerung },
                set: { keynote.inAbklaerung = !$0 }
            ))

            if !keynote.inAbklaerung {
                DatePicker("Datum", selection: $keynote.eventDate, displayedComponents: .date)
                DatePicker("Zeit", selection: $keynote.eventDate, displayedComponents: .hourAndMinute)
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Firma/Organisation", text: $keynote.clientOrganization)
            
            HStack {
                Text("Honorar")
                Spacer()
                TextField("Betrag", value: $keynote.agreedFee, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                Text("CHF")
            }
            
            TextField("Zielpublikum", text: $keynote.targetAudience)

            HStack {
                Text("Anzahl Zuhörer")
                Spacer()
                TextField("Anzahl", value: $keynote.attendeeCount, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            TextField("Ort", text: $keynote.location)
            
            DatePicker("Anfragedatum", selection: $keynote.requestDate, displayedComponents: .date)
        }
    }
    
    private var contactSection: some View {
        Section("Kontakt") {
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
    
    private var pendenzSection: some View {
        Section("Pendenz") {
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
    
    private var statusSection: some View {
        Section("Status") {
            HStack {
                Circle()
                    .fill(keynote.status.color)
                    .frame(width: 12, height: 12)
                Text(keynote.status.rawValue)
                Spacer()
            }
            
            if !keynote.status.nextStatus.isEmpty {
                Button("Status ändern") {
                    showingStatusChange = true
                }
            }
            
            if keynote.calendarEventID != nil {
                Label("Kalender-Eintrag vorhanden", systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.green)
            } else if keynote.status == .dateConfirmedFeeOffered || keynote.status.rawValue > KeynoteStatus.dateConfirmedFeeOffered.rawValue {
                Button("Save the Date erstellen") {
                    Task {
                        do {
                            if let eventID = try await calendarService.createSaveTheDate(for: keynote) {
                                keynote.calendarEventID = eventID
                                showingSaveCalendarAlert = true
                            }
                        } catch {
                            print("Fehler beim Erstellen des Kalender-Eintrags: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    private var availabilitySection: some View {
        Section("Verfügbarkeit") {
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
            } else if isCheckingAvailability == false && !availabilityEvents.isEmpty == false {
                Label("Keine Konflikte gefunden", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notizen") {
            TextEditor(text: $keynote.notes)
                .frame(minHeight: 100)
        }
    }
    
    private func saveNewKeynote() {
        modelContext.insert(keynote)
        onSave?()
    }
    
    private func checkAvailability() {
        isCheckingAvailability = true
        
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
                let timeString = formatter.string(from: event.startDate)
                return "\(timeString): \(event.title ?? "Unbekannt")"
            }
            
            isCheckingAvailability = false
        }
    }
}

// MARK: - Status Change View
struct StatusChangeView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var keynote: Keynote
    var calendarService: CalendarService
    
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
        }
    }
    
    private func updateStatus(to status: KeynoteStatus, createCalendarEvent: Bool) {
        keynote.status = status
        
        if createCalendarEvent {
            Task {
                do {
                    if let eventID = try await calendarService.createSaveTheDate(for: keynote) {
                        keynote.calendarEventID = eventID
                    }
                } catch {
                    print("Fehler beim Erstellen des Kalender-Eintrags: \(error)")
                }
            }
        }
        
        dismiss()
    }
}

// MARK: - Contact Display View
struct ContactDisplayView: View {
    let contactID: String?
    @ObservedObject var contactsService: ContactsService
    let onChangeContact: () -> Void
    
    @State private var contactName: String = "Lädt..."
    @State private var contactEmail: String?
    @State private var contactPhone: String?
    
    var body: some View {
        if let contactID = contactID {
            HStack {
                VStack(alignment: .leading) {
                    Text(contactName)
                        .font(.headline)
                        .redacted(reason: contactName == "Lädt..." ? .placeholder : [])
                    
                    if let email = contactEmail {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let phone = contactPhone {
                        Text(phone)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Ändern") {
                    onChangeContact()
                }
            }
            .task(id: contactID) {
                // Lade Kontaktdaten asynchron
                await loadContactData(contactID: contactID)
            }
        } else {
            Button(action: onChangeContact) {
                Label("Primären Kontakt wählen", systemImage: "person.crop.circle.badge.plus")
            }
        }
    }
    
    private func loadContactData(contactID: String) async {
        // Capture the service to avoid dynamic member lookup issues in async context
        let service = contactsService
        
        // Load contact data - these methods are synchronous but marked @MainActor
        let loadedName = service.getContactName(identifier: contactID)
        let loadedEmail = service.getContactEmail(identifier: contactID)
        let loadedPhone = service.getContactPhone(identifier: contactID)
        
        // Update UI
        self.contactName = loadedName
        self.contactEmail = loadedEmail
        self.contactPhone = loadedPhone
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        KeynoteDetailView(keynote: Keynote(), isNewKeynote: true)
    }
    .modelContainer(for: Keynote.self, inMemory: true)
}

