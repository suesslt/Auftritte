//
//  KeynoteStatsView.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import SwiftUI
import SwiftData

struct KeynoteStatsView: View {
    @Query private var keynotes: [Keynote]
    
    private var stats: KeynoteStatistics {
        KeynoteStatistics(keynotes: keynotes)
    }
    
    var body: some View {
        List {
            Section("Übersicht") {
                StatRow(
                    title: "Gesamt Auftritte",
                    value: "\(stats.totalKeynotes)",
                    icon: "mic.fill",
                    color: .blue
                )
                
                StatRow(
                    title: "Dieses Jahr",
                    value: "\(stats.keynotesThisYear)",
                    icon: "calendar",
                    color: .green
                )
                
                StatRow(
                    title: "Anstehende Auftritte",
                    value: "\(stats.upcomingKeynotes)",
                    icon: "clock.fill",
                    color: .orange
                )
                
                StatRow(
                    title: "Abgeschlossene",
                    value: "\(stats.completedKeynotes)",
                    icon: "checkmark.circle.fill",
                    color: .purple
                )
            }
            
            Section("Finanzen") {
                StatRow(
                    title: "Gesamt-Honorar (bestätigt)",
                    value: formatCurrency(stats.totalConfirmedFees),
                    icon: "banknote.fill",
                    color: .green
                )
                
                StatRow(
                    title: "Offene Honorare",
                    value: formatCurrency(stats.pendingFees),
                    icon: "clock.badge.exclamationmark.fill",
                    color: .orange
                )
                
                StatRow(
                    title: "Bezahlt",
                    value: formatCurrency(stats.paidFees),
                    icon: "checkmark.circle.fill",
                    color: .mint
                )
            }
            
            Section("Status Verteilung") {
                ForEach(stats.statusDistribution.sorted(by: { $0.count > $1.count }), id: \.status) { item in
                    HStack {
                        Circle()
                            .fill(item.status.color)
                            .frame(width: 12, height: 12)
                        
                        Text(item.status.rawValue)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text("\(item.count)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Statistiken")
    }
    
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: value as NSDecimalNumber) ?? "0"
        return "\(formatted) CHF"
    }
}

struct StatRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 30)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.headline)
        }
    }
}

// MARK: - Statistics Model
struct KeynoteStatistics {
    let keynotes: [Keynote]
    
    var totalKeynotes: Int {
        keynotes.count
    }
    
    var keynotesThisYear: Int {
        let currentYear = Calendar.current.component(.year, from: Date())
        return keynotes.filter { keynote in
            Calendar.current.component(.year, from: keynote.eventDate) == currentYear
        }.count
    }
    
    var upcomingKeynotes: Int {
        keynotes.filter { keynote in
            keynote.eventDate > Date() && keynote.status != .cancelled && keynote.status != .closed
        }.count
    }
    
    var completedKeynotes: Int {
        keynotes.filter { $0.status == .closed }.count
    }
    
    var totalConfirmedFees: Decimal {
        keynotes.filter { keynote in
            keynote.status.rawValue >= KeynoteStatus.feeConfirmed.rawValue &&
            keynote.status != .cancelled
        }.reduce(0) { $0 + $1.agreedFee }
    }
    
    var pendingFees: Decimal {
        keynotes.filter { keynote in
            keynote.status == .completedInvoiced
        }.reduce(0) { $0 + $1.agreedFee }
    }
    
    var paidFees: Decimal {
        keynotes.filter { keynote in
            keynote.status == .paid || keynote.status == .feedbackRequested || keynote.status == .closed
        }.reduce(0) { $0 + $1.agreedFee }
    }
    
    var statusDistribution: [(status: KeynoteStatus, count: Int)] {
        let grouped = Dictionary(grouping: keynotes, by: { $0.status })
        return grouped.map { (status: $0.key, count: $0.value.count) }
    }
}

#Preview {
    NavigationStack {
        KeynoteStatsView()
            .modelContainer(for: Keynote.self, inMemory: true)
    }
}
