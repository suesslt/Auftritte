//
//  KeynoteContact.swift
//  Auftritte
//
//  Created by Thomas Süssli on 09.02.2026.
//

import Foundation
import SwiftData

/// Embedded contact information that syncs across devices via iCloud
@Model
final class KeynoteContact {
    var fullName: String = ""
    var email: String = ""
    var phone: String = ""
    
    // Optional: Store original contact ID for linking back to Contacts app on this device
    // This won't work cross-device, but useful for "Open in Contacts" feature
    var localContactID: String?
    
    // Inverse relationship required for CloudKit sync
    @Relationship(inverse: \Keynote.primaryContact)
    var keynotes: [Keynote]? = []
    
    init(
        fullName: String = "",
        email: String = "",
        phone: String = "",
        localContactID: String? = nil
    ) {
        self.fullName = fullName
        self.email = email
        self.phone = phone
        self.localContactID = localContactID
    }
    
    /// Check if contact has meaningful data
    var hasData: Bool {
        !fullName.isEmpty || !email.isEmpty || !phone.isEmpty
    }
    
    /// Get display name with fallback
    var displayName: String {
        fullName.isEmpty ? "Unbekannter Kontakt" : fullName
    }
}
