//
//  ContactPickerView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 09.02.2026.
//

import SwiftUI
import Contacts
import Combine

// MARK: - ViewModel
@MainActor
class ContactPickerViewModel: ObservableObject {
    @Published var contacts: [CNContact] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let contactsService: ContactsService
    
    init(contactsService: ContactsService) {
        self.contactsService = contactsService
    }
    
    var filteredContacts: [CNContact] {
        if searchText.isEmpty {
            return contacts
        }
        
        return contacts.filter { contact in
            let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let organization = contact.organizationName
            let email = contact.emailAddresses.first?.value as String? ?? ""
            
            let searchLower = searchText.lowercased()
            
            return fullName.lowercased().contains(searchLower) ||
                   organization.lowercased().contains(searchLower) ||
                   email.lowercased().contains(searchLower)
        }
    }
    
    func loadContacts() async {
        isLoading = true
        errorMessage = nil
        
        // Request access first
        let hasAccess = await contactsService.requestAccess()
        
        guard hasAccess else {
            errorMessage = "Zugriff auf Kontakte wurde verweigert. Bitte aktivieren Sie den Zugriff in den Systemeinstellungen."
            isLoading = false
            return
        }
        
        // Fetch all contacts
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        ]
        
        let fetchRequest = CNContactFetchRequest(keysToFetch: keysToFetch)
        fetchRequest.sortOrder = .familyName
        
        do {
            // Move the blocking contact enumeration to a background thread
            let fetchedContacts = try await withCheckedThrowingContinuation { continuation in
                Task.detached {
                    do {
                        var contacts: [CNContact] = []
                        let contactStore = CNContactStore()
                        
                        try contactStore.enumerateContacts(with: fetchRequest) { contact, _ in
                            contacts.append(contact)
                        }
                        
                        continuation.resume(returning: contacts)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            contacts = fetchedContacts
            isLoading = false
        } catch {
            errorMessage = "Fehler beim Laden der Kontakte: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

// MARK: - View
/// Native SwiftUI Contact Picker für iOS und macOS
struct ContactPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ContactPickerViewModel
    
    let contactsService: ContactsService
    let onContactSelected: (KeynoteContact) -> Void
    
    init(contactsService: ContactsService, onContactSelected: @escaping (KeynoteContact) -> Void) {
        self.contactsService = contactsService
        self.onContactSelected = onContactSelected
        self._viewModel = StateObject(wrappedValue: ContactPickerViewModel(contactsService: contactsService))
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let error = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Fehler", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Erneut versuchen") {
                            Task {
                                await viewModel.loadContacts()
                            }
                        }
                    }
                } else if viewModel.isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Kontakte werden geladen...")
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.filteredContacts.isEmpty {
                    if viewModel.searchText.isEmpty {
                        ContentUnavailableView(
                            "Keine Kontakte",
                            systemImage: "person.slash",
                            description: Text("Es wurden keine Kontakte gefunden.")
                        )
                    } else {
                        ContentUnavailableView.search
                    }
                } else {
                    contactList
                }
            }
            .navigationTitle("Kontakt wählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Kontakte durchsuchen...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.loadContacts()
        }
    }
    
    private var contactList: some View {
        List {
            ForEach(viewModel.filteredContacts, id: \.identifier) { contact in
                ContactRowButton(contact: contact) {
                    // Erstelle KeynoteContact aus CNContact
                    if let keynoteContact = contactsService.createKeynoteContact(from: contact.identifier) {
                        onContactSelected(keynoteContact)
                        dismiss()
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Contact Row Button
struct ContactRowButton: View {
    let contact: CNContact
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Avatar oder Initialen
                contactAvatar
                
                // Kontakt-Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(CNContactFormatter.string(from: contact, style: .fullName) ?? "Unbekannt")
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    if !contact.organizationName.isEmpty {
                        Text(contact.organizationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let email = contact.emailAddresses.first?.value as? String {
                        Text(email)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var contactAvatar: some View {
        if let imageData = contact.imageData,
           let image = platformImage(from: imageData) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        } else {
            // Initialen
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Text(initials)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
    }
    
    private var initials: String {
        let firstName = contact.givenName.prefix(1)
        let lastName = contact.familyName.prefix(1)
        return "\(firstName)\(lastName)".uppercased()
    }
    
    #if os(macOS)
    private func platformImage(from data: Data) -> NSImage? {
        NSImage(data: data)
    }
    #else
    private func platformImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }
    #endif
}

// MARK: - Platform Image Extension
extension Image {
    #if os(macOS)
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
    #else
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
    #endif
}

// MARK: - Preview
#Preview("Contact Picker") {
    ContactPickerView(
        contactsService: ContactsService(),
        onContactSelected: { contact in
            print("Kontakt ausgewählt: \(contact.displayName)")
        }
    )
}
#Preview("Contact Row") {
    let contact = CNMutableContact()
    contact.givenName = "Max"
    contact.familyName = "Mustermann"
    contact.organizationName = "Musterfirma AG"
    contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "max@example.com" as NSString)]
    
    return List {
        ContactRowButton(contact: contact) {
            print("Kontakt ausgewählt")
        }
    }
}


