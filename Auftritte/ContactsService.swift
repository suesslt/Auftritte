//
//  ContactsService.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import Foundation
import Combine
import Contacts
import ContactsUI

@MainActor
class ContactsService: ObservableObject {
    nonisolated(unsafe) private let contactStore = CNContactStore()
    @Published var authorizationStatus: CNAuthorizationStatus
    
    init() {
        self.authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
            return granted
        } catch {
            print("Fehler beim Anfordern des Kontaktzugriffs: \(error)")
            return false
        }
    }
    
    nonisolated func getContact(identifier: String) -> CNContact? {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        ]
        
        do {
            return try contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keysToFetch)
        } catch let error as NSError {
            // Kontakt existiert nicht mehr (CNErrorCode 200 = record does not exist)
            if error.domain == CNErrorDomain && error.code == 200 {
                // Stiller Fehler - Kontakt wurde gelöscht, das ist okay
                return nil
            }
            print("Fehler beim Laden des Kontakts: \(error)")
            return nil
        }
    }
    
    nonisolated func getContactName(identifier: String) -> String {
        guard let contact = getContact(identifier: identifier) else {
            return "Unbekannt"
        }
        
        let formatter = CNContactFormatter()
        return formatter.string(from: contact) ?? "Unbekannt"
    }
    
    nonisolated func getContactEmail(identifier: String) -> String? {
        guard let contact = getContact(identifier: identifier),
              let firstEmail = contact.emailAddresses.first else {
            return nil
        }
        
        return firstEmail.value as String
    }
    
    nonisolated func getContactPhone(identifier: String) -> String? {
        guard let contact = getContact(identifier: identifier),
              let firstPhone = contact.phoneNumbers.first else {
            return nil
        }
        
        return firstPhone.value.stringValue
    }
    
    /// Schreibt die Kontaktdaten eines CNContact direkt auf eine Keynote.
    nonisolated func applyContact(from identifier: String, to keynote: Keynote) {
        guard let contact = getContact(identifier: identifier) else { return }
        
        let formatter = CNContactFormatter()
        keynote.contactFullName = formatter.string(from: contact) ?? ""
        keynote.contactEmail    = contact.emailAddresses.first?.value as String? ?? ""
        keynote.contactPhone    = contact.phoneNumbers.first?.value.stringValue ?? ""
        keynote.contactLocalID  = identifier
    }
    
    /// Try to find a matching CNContact for a Keynote's embedded contact data.
    /// This enables "Open in Contacts" feature even on different devices
    /// by matching name and email/phone
    nonisolated func findMatchingContact(for keynote: Keynote) -> String? {
        // First try the stored local ID (works if on same device)
        if let localID = keynote.contactLocalID,
           getContact(identifier: localID) != nil {
            return localID
        }
        
        // Otherwise try to find by email or name
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        
        do {
            var foundID: String?
            try contactStore.enumerateContacts(with: request) { contact, stop in
                if !keynote.contactEmail.isEmpty {
                    for emailAddr in contact.emailAddresses {
                        if (emailAddr.value as String).lowercased() == keynote.contactEmail.lowercased() {
                            foundID = contact.identifier
                            stop.pointee = true
                            return
                        }
                    }
                }
                
                let formatter = CNContactFormatter()
                if let contactName = formatter.string(from: contact),
                   contactName == keynote.contactFullName {
                    foundID = contact.identifier
                    stop.pointee = true
                }
            }
            return foundID
        } catch {
            print("Fehler beim Suchen des Kontakts: \(error)")
            return nil
        }
    }
}
