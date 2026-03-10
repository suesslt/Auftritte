# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Auftritte is an iOS/macOS app for managing keynote speeches and presentations. It tracks speaking engagements from initial inquiry through payment, including event details, contact information, fees, calendar integration, and status workflows. German-language UI ("Auftritte" = "Performances").

## Build & Test Commands

```bash
# Build
xcodebuild -project Auftritte.xcodeproj -scheme Auftritte build

# Run tests
xcodebuild -project Auftritte.xcodeproj -scheme Auftritte test
```

## Architecture

- **SwiftUI + SwiftData** with CloudKit sync
- **NavigationSplitView** with sidebar list and detail pane
- **Service layer**: CalendarService (EventKit), ContactsService for external integrations

### Key Files

| File | Role |
|------|------|
| `AuftritteApp.swift` | Entry point, SwiftData ModelContainer setup |
| `ContentView.swift` | Root view with split view, filtering, search |
| `Keynote.swift` | @Model — core data entity for speaking engagements |
| `AuftritteStatus.swift` | Status enums (KeynoteStatus, KeynoteSection, Pendenz) |
| `AuftritteDetailView.swift` | Edit/create keynote form |
| `CSVImporter.swift` / `CSVExporter.swift` | CSV import/export |
| `AuftrittePDFGenerator.swift` | PDF export |
| `CalendarService.swift` | EventKit calendar integration |

### Features

- Status workflow with color coding (date pending → speaker pending → client pending → ready → completed)
- Smart filtering: status filter + full-text search across 8 fields
- CSV import/export, PDF export
- Calendar integration (EventKit), Contacts picker
- Swipe actions and context menus

## Score Package — Shared Base Classes

This project depends on the [Score](../score) package via local SPM dependency (`../score`).

**Current usage**: `import ScoreUI` for `ErrorHandler` and `.errorAlert()` modifier.

### Available Types

| Type | Module | Description |
|------|--------|-------------|
| `Money` | Score | Currency-safe monetary amounts with `Decimal` precision. Arithmetic enforces matching currencies. |
| `Currency` | Score | ISO 4217 enum with 180+ currencies, decimal places, and localized names. |
| `Percent` | Score | Percentage as factor (e.g. `0.10` = 10%). |
| `FXRate` | Score | Bid/ask exchange rates with conversion methods. |
| `VATCalculation` | Score | VAT split (net/gross) with inclusive/exclusive handling. |
| `YearMonth` | Score | Year-month value type for monthly periods. |
| `DayCountRule` | Score | Financial day count conventions (ACT/360, ACT/365, 30/360). |
| `ServicePipeline` | Score | Async middleware chain for service operations. |
| `ServiceError` | Score | Typed errors (notFound, validation, businessRule, etc.). |
| `CSVExportable` | Score | Protocol for CSV row export. |
| `IBANValidator` | Score | ISO 13616 IBAN validation. |
| `SCORReferenceGenerator` | Score | ISO 11649 creditor reference with Mod 97. |
| `ErrorHandler` | ScoreUI | Observable error state management for SwiftUI. |
| `PDFRenderer` | ScoreUI | UIKit-based PDF generation. |
| `.errorAlert()` | ScoreUI | SwiftUI modifier for error alert presentation. |

```swift
import Score    // Core financial types
import ScoreUI  // ErrorHandler, PDFRenderer, .errorAlert()
```
