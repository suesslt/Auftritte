//
//  KeynoteListItemView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import SwiftUI

/// Separate View-Komponente für bessere Performance bei langen Listen
struct KeynoteListItemView: View {
    let keynote: Keynote
    let contactName: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header mit Name und Status
            HStack {
                Text(keynote.eventName)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 4) {
                    if keynote.calendarEventID != nil {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    
                    Circle()
                        .fill(Color(keynote.status.color))
                        .frame(width: 10, height: 10)
                }
            }
            
            // Titel
            Text(keynote.keynoteTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            // Datum und Ort
            HStack(spacing: 8) {
                Label {
                    Text(keynote.eventDate.formatted(date: .abbreviated, time: .shortened))
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption)
                
                if !keynote.location.isEmpty {
                    Label {
                        Text(keynote.location)
                    } icon: {
                        Image(systemName: "mappin.circle")
                    }
                    .font(.caption)
                    .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)
            
            // Organisation, Kontakt und Honorar
            HStack(spacing: 4) {
                if !keynote.clientOrganization.isEmpty {
                    Text(keynote.clientOrganization)
                        .font(.caption)
                        .lineLimit(1)
                }
                
                if let name = contactName {
                    Text("•")
                        .font(.caption)
                    Text(name)
                        .font(.caption)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if keynote.agreedFee > 0 {
                    Text(formatCurrency(keynote.agreedFee))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: value as NSDecimalNumber) ?? "0"
        return "\(formatted) CHF"
    }
}

#Preview {
    List {
        KeynoteListItemView(
            keynote: Keynote(
                eventName: "Tech Conference 2026",
                eventDate: Date(),
                keynoteTitle: "Die Zukunft der KI",
                keynoteTheme: "Künstliche Intelligenz",
                duration: 45,
                clientOrganization: "Tech Corp AG",
                agreedFee: 5000,
                location: "Zürich"
            ),
            contactName: "Max Mustermann"
        )
    }
}
