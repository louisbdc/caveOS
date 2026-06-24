import SwiftUI
import SafariServices

/// Présente une URL (Stripe Checkout / Customer Portal) dans un navigateur in-app sécurisé.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Enveloppe `Identifiable` pour présenter une URL via `.sheet(item:)`.
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
