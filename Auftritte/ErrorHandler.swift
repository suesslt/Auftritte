//
//  ErrorHandler.swift
//  Auftritte
//
//  Created by Thomas Süssli on 08.02.2026.
//

import SwiftUI
import Combine

/// Error Handler für bessere Fehlerbehandlung und User Feedback
@MainActor
class ErrorHandler: ObservableObject {
    @Published var currentError: ErrorWrapper?
    @Published var isShowingError = false
    
    func handle(_ error: Error, title: String = "Fehler", message: String? = nil) {
        currentError = ErrorWrapper(
            error: error,
            title: title,
            message: message ?? error.localizedDescription
        )
        isShowingError = true
    }
}

struct ErrorWrapper: Identifiable {
    let id = UUID()
    let error: Error
    let title: String
    let message: String
}

/// ViewModifier für Error Handling
struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorHandler: ErrorHandler
    
    func body(content: Content) -> some View {
        content
            .alert(
                errorHandler.currentError?.title ?? "Fehler",
                isPresented: $errorHandler.isShowingError,
                presenting: errorHandler.currentError
            ) { _ in
                Button("OK", role: .cancel) {
                    errorHandler.currentError = nil
                }
            } message: { error in
                Text(error.message)
            }
    }
}

extension View {
    func errorAlert(errorHandler: ErrorHandler) -> some View {
        modifier(ErrorAlertModifier(errorHandler: errorHandler))
    }
}
