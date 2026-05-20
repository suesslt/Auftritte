//
//  AuftritteTableView.swift
//  Auftritte
//
//  Tabellarische Ansicht aller Auftritte mit sortierbaren Spalten und
//  individuell per Drag-Handle anpassbaren Spaltenbreiten (persistent).
//

import SwiftUI
import SwiftData

// MARK: - Persistenz-Wrapper für Spaltenbreiten

private struct ColumnWidths: RawRepresentable, Codable {
    var values: [CGFloat]

    init(values: [CGFloat]) { self.values = values }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CGFloat].self, from: data)
        else { return nil }
        self.values = decoded
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(values),
              let str = String(data: data, encoding: .utf8)
        else { return "[]" }
        return str
    }
}

// MARK: - View

struct AuftritteTableView: View {
    let keynotes: [Keynote]
    @Binding var selection: Keynote.ID?
    let onUpdateStatus: (Keynote, KeynoteStatus) -> Void
    let onDelete: (Keynote) -> Void

    @State private var sortKey: SortKey = .eventDate
    @State private var sortAscending: Bool = true

    @AppStorage("auftritteTableColumnWidths")
    private var storedWidths = ColumnWidths(values: AuftritteTableView.defaultWidths)

    @State private var dragStartWidths: [Int: CGFloat] = [:]

    private enum SortKey {
        case eventDate, eventName, keynoteTheme, contactLastName, agreedFee, statusRaw
    }

    // MARK: - Spalten-Konfiguration

    private struct ColumnConfig {
        let title: String
        let defaultWidth: CGFloat
        let key: SortKey
        let alignment: HorizontalAlignment
    }

    private static let defaultWidths: [CGFloat] = [110, 200, 220, 240, 110, 180]
    private static let minColumnWidth: CGFloat = 60
    private static let handleWidth: CGFloat = 6
    private static let columnSpacing: CGFloat = 16

    private let columns: [ColumnConfig] = [
        .init(title: "Datum",         defaultWidth: 110, key: .eventDate,       alignment: .leading),
        .init(title: "Anlass",        defaultWidth: 200, key: .eventName,       alignment: .leading),
        .init(title: "Thema",         defaultWidth: 220, key: .keynoteTheme,    alignment: .leading),
        .init(title: "Kontaktperson", defaultWidth: 240, key: .contactLastName, alignment: .leading),
        .init(title: "Honorar",       defaultWidth: 110, key: .agreedFee,       alignment: .trailing),
        .init(title: "Status",        defaultWidth: 180, key: .statusRaw,       alignment: .leading)
    ]

    private func width(at idx: Int) -> CGFloat {
        guard idx < storedWidths.values.count else { return columns[idx].defaultWidth }
        return storedWidths.values[idx]
    }

    private var totalWidth: CGFloat {
        (0..<columns.count).reduce(0) { $0 + width(at: $1) } + CGFloat(columns.count) * Self.columnSpacing
    }

    private var sortedKeynotes: [Keynote] {
        keynotes.sorted { lhs, rhs in
            let result: Bool
            switch sortKey {
            case .eventDate:        result = lhs.eventDate < rhs.eventDate
            case .eventName:        result = lhs.eventName.localizedCompare(rhs.eventName) == .orderedAscending
            case .keynoteTheme:     result = lhs.keynoteTheme.localizedCompare(rhs.keynoteTheme) == .orderedAscending
            case .contactLastName:
                let lastCompare = lhs.contactLastName.localizedCompare(rhs.contactLastName)
                if lastCompare == .orderedSame {
                    result = lhs.contactFirstName.localizedCompare(rhs.contactFirstName) == .orderedAscending
                } else {
                    result = lastCompare == .orderedAscending
                }
            case .agreedFee:        result = lhs.agreedFeeInCents < rhs.agreedFeeInCents
            case .statusRaw:        result = lhs.statusRaw.localizedCompare(rhs.statusRaw) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                headerRow
                Divider()
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedKeynotes) { keynote in
                            dataRow(for: keynote)
                            Divider()
                        }
                    }
                }
            }
            .frame(width: totalWidth, alignment: .leading)
        }
        .contextMenu {
            Button("Spaltenbreiten zurücksetzen", systemImage: "arrow.counterclockwise") {
                resetWidths()
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: Self.columnSpacing) {
            ForEach(columns.indices, id: \.self) { idx in
                let column = columns[idx]
                HStack(spacing: 0) {
                    Button(action: { toggleSort(column.key) }) {
                        headerLabel(for: column)
                            .frame(
                                width: max(0, width(at: idx) - Self.handleWidth),
                                alignment: column.alignment == .leading ? .leading : .trailing
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    resizeHandle(for: idx)
                }
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.12))
    }

    private func headerLabel(for column: ColumnConfig) -> some View {
        HStack(spacing: 4) {
            if column.alignment == .trailing { Spacer(minLength: 0) }
            Text(column.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if sortKey == column.key {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            if column.alignment == .leading { Spacer(minLength: 0) }
        }
    }

    private func resizeHandle(for idx: Int) -> some View {
        let handle = Rectangle()
            .fill(Color.clear)
            .frame(width: Self.handleWidth)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidths[idx] == nil {
                            dragStartWidths[idx] = width(at: idx)
                        }
                        let start = dragStartWidths[idx] ?? width(at: idx)
                        let newWidth = max(Self.minColumnWidth, start + value.translation.width)
                        var values = storedWidths.values
                        while values.count <= idx {
                            values.append(columns[values.count].defaultWidth)
                        }
                        values[idx] = newWidth
                        storedWidths = ColumnWidths(values: values)
                    }
                    .onEnded { _ in
                        dragStartWidths[idx] = nil
                    }
            )

        #if os(macOS)
        return handle.onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        #else
        return handle
        #endif
    }

    // MARK: - Datenzeile

    private func dataRow(for keynote: Keynote) -> some View {
        HStack(spacing: Self.columnSpacing) {
            cell(idx: 0) {
                Text(keynote.eventDate, format: .dateTime.day().month().year())
            }
            cell(idx: 1) {
                Text(keynote.eventName).lineLimit(1)
            }
            cell(idx: 2) {
                Text(keynote.keynoteTheme).lineLimit(1)
            }
            cell(idx: 3) {
                Text(Self.formatContact(keynote)).lineLimit(1)
            }
            cell(idx: 4) {
                Text(Self.formatFee(keynote.agreedFee)).monospacedDigit()
            }
            cell(idx: 5) {
                HStack(spacing: 6) {
                    Circle().fill(keynote.status.color).frame(width: 10, height: 10)
                    Text(keynote.status.rawValue).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selection == keynote.id ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = keynote.id
        }
        .contextMenu {
            Menu {
                ForEach(KeynoteStatus.allCases) { status in
                    Button {
                        onUpdateStatus(keynote, status)
                    } label: {
                        HStack {
                            Text(status.rawValue)
                            if keynote.status == status {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Status ändern", systemImage: "circle.fill")
            }

            Button(role: .destructive) {
                onDelete(keynote)
            } label: {
                Label("Auftritt löschen", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func cell<Content: View>(idx: Int, @ViewBuilder content: () -> Content) -> some View {
        let alignment = columns[idx].alignment
        content()
            .frame(
                width: width(at: idx),
                alignment: alignment == .leading ? .leading : .trailing
            )
    }

    // MARK: - Sortierung

    private func toggleSort(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
    }

    // MARK: - Reset

    private func resetWidths() {
        storedWidths = ColumnWidths(values: Self.defaultWidths)
    }

    // MARK: - Formatter

    private static func formatContact(_ keynote: Keynote) -> String {
        let first = keynote.contactFirstName.trimmingCharacters(in: .whitespaces)
        let last  = keynote.contactLastName.trimmingCharacters(in: .whitespaces)
        let name: String
        switch (first.isEmpty, last.isEmpty) {
        case (false, false): name = "\(last), \(first)"
        case (true,  false): name = last
        case (false, true):  name = first
        case (true,  true):  name = keynote.contactFullName.trimmingCharacters(in: .whitespaces)
        }
        let phone = keynote.contactPhone.trimmingCharacters(in: .whitespaces)
        switch (name.isEmpty, phone.isEmpty) {
        case (false, false): return "\(name) — \(phone)"
        case (false, true):  return name
        case (true,  false): return phone
        case (true,  true):  return ""
        }
    }

    private static func formatFee(_ value: Decimal) -> String {
        guard value > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: value as NSDecimalNumber) ?? "0"
        return "\(formatted) CHF"
    }
}

#Preview {
    @Previewable @State var selection: Keynote.ID?
    return AuftritteTableView(
        keynotes: [],
        selection: $selection,
        onUpdateStatus: { _, _ in },
        onDelete: { _ in }
    )
    .modelContainer(previewContainer())
}
