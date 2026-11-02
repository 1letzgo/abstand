import Combine
import StoreKit
import SwiftUI
import os

/// Freiwillige Trinkgeld-Stufen (Consumables, wie in stashy) — schalten nichts frei.
/// Reihenfolge der Fälle = Anzeigereihenfolge; Preise kommen immer aus dem App Store.
enum TipTier: String, CaseIterable, Identifiable {
  case small = "de.abstand.tip1"
  case medium = "de.abstand.tip2"
  case large = "de.abstand.tip3"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .small: return "Small"
    case .medium: return "Medium"
    case .large: return "Large"
    }
  }

  var icon: String {
    switch self {
    case .small: return "heart"
    case .medium: return "heart.fill"
    case .large: return "bolt.heart.fill"
    }
  }
}

struct TipOffer: Identifiable {
  let tier: TipTier
  let product: Product

  var id: String { tier.id }
}

enum TipPurchaseOutcome {
  case completed
  case pending
  case cancelled
}

/// Eigenständig statt in `AppModel`: Kaufzustand soll nicht an dessen `@Published`-Properties hängen.
@MainActor
final class TipStore: ObservableObject {
  static let shared = TipStore()

  @Published private(set) var offers: [TipOffer] = []
  @Published private(set) var isLoading = false

  private var transactionListener: Task<Void, Never>?

  private init() {}

  /// Beim App-Start aufrufen: fängt spät eintreffende Käufe ab (Ask to Buy, abgebrochene Abschlüsse).
  func startTransactionListener() {
    guard transactionListener == nil else { return }
    transactionListener = Task.detached(priority: .background) {
      for await result in StoreKit.Transaction.updates {
        // Trinkgeld liefert nichts aus — geprüfte Transaktionen nur noch abschließen.
        guard case .verified(let transaction) = result else { continue }
        await transaction.finish()
      }
    }
  }

  func loadOffersIfNeeded() async {
    guard offers.count < TipTier.allCases.count, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let products = try await Product.products(for: TipTier.allCases.map(\.rawValue))
      offers = TipTier.allCases.compactMap { tier in
        products.first { $0.id == tier.rawValue }.map { TipOffer(tier: tier, product: $0) }
      }
    } catch {
      AppLog.debug.error("Tip products failed to load: \(error.localizedDescription, privacy: .public)")
    }
  }

  func complete(_ result: Product.PurchaseResult) async throws -> TipPurchaseOutcome {
    switch result {
    case .success(let verification):
      let transaction = try verification.payloadValue
      await transaction.finish()
      return .completed
    case .pending:
      return .pending
    case .userCancelled:
      return .cancelled
    @unknown default:
      return .cancelled
    }
  }
}

// MARK: - Einmaliges Angebot beim Start

/// Zeigt das Angebot genau einmal, sobald die App steht. Läuft erst nach dem Bootstrap und ohne
/// Vorrang vor dem Vollbild-Player; ohne geladene Produkte (offline) bleibt es für den nächsten Start offen.
struct TipOfferLaunchModifier: ViewModifier {
  @EnvironmentObject private var model: AppModel
  @State private var isPresented = false

  private static let settleDelay: Duration = .seconds(3)

  private var isBlocked: Bool {
    model.isAppBootstrapInProgress
      || model.showsServerConnectionConnectingOverlay
      || model.isNowPlayingOverlayVisible
      || model.isSwitchingAccount
  }

  func body(content: Content) -> some View {
    content
      .task(id: isBlocked) {
        guard !isBlocked, !UserDefaults.standard.bool(forKey: AppModel.Keys.tipOfferShown) else { return }
        guard (try? await Task.sleep(for: Self.settleDelay)) != nil else { return }
        await TipStore.shared.loadOffersIfNeeded()
        guard !Task.isCancelled, !TipStore.shared.offers.isEmpty else { return }
        isPresented = true
      }
      .sheet(isPresented: $isPresented) {
        TipOfferSheet()
      }
  }
}

private struct TipOfferSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let _ = model.appearanceThemeRevision
    NavigationStack {
      MetadataSheetScrollScreen {
        Text("abstand is a hobby project. If you enjoy it, you can leave a voluntary tip. Tips don't unlock anything.")
          .font(.body)
          .foregroundStyle(model.appearancePalette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        TipOptionsCard(onThanked: { dismiss() })
      }
      .navigationTitle("Support abstand")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Not now") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .tint(model.appearanceAccentColor)
    .themeAccentFromAppModel(model)
    // Erst hier merken: Konnte das Sheet nicht erscheinen, bleibt das Angebot offen.
    .onAppear {
      UserDefaults.standard.set(true, forKey: AppModel.Keys.tipOfferShown)
    }
  }
}
