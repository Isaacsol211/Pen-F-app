import Foundation
import StoreKit

/// Shutterlink Pro: a one-time purchase that unlocks the tools that do the work for you (setups,
/// time-lapse, bracketing and focus stacks, ND, expose to the right, the motion trigger, High Res
/// helper, the Apple Watch remote and the scene suggestions that run a setup). Everything a camera
/// maker's own app does stays free.
///
/// Unlocked by any of:
/// - the Pro purchase (non-consumable, shared across iPhone, iPad and Mac by universal purchase);
/// - the 7-day trial: a free non-consumable, the App Review guideline 3.1.1 way to try a one-time
///   purchase. The trial runs from its purchase date;
/// - being an early user: anyone who first installed version 1.0 (builds 1–4), which had everything
///   free, keeps Pro.
@MainActor
@Observable
final class ShutterlinkPro {
    static let shared = ShutterlinkPro()

    static let proID = "com.apexcommerce.shutterlink.pro"
    static let trialID = "com.apexcommerce.shutterlink.pro.trial"
    static let trialDays = 7
    /// iOS reports the original install as its build number (CFBundleVersion). 1.0 shipped as builds 1–4;
    /// the first build with Pro must be 5 or later.
    static let lastFreeBuild = 4
    /// The Mac reports the original install as its version. The Mac app first ships in 1.1, with Pro.
    static let firstPaidVersion = "1.1"

    private(set) var purchased = false
    private(set) var trialStarted: Date?
    private(set) var earlyUser = false
    private(set) var products: [String: Product] = [:]
    private(set) var busy = false
    var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?
    #if DEBUG
    /// `-pro locked|unlocked|trial` pins the state, for trying the locks and the Pro screen.
    @ObservationIgnored private let override = UserDefaults.standard.string(forKey: "pro")
    #endif

    var trialEnds: Date? {
        trialStarted.flatMap { Calendar.current.date(byAdding: .day, value: Self.trialDays, to: $0) }
    }
    var inTrial: Bool { (trialEnds ?? .distantPast) > Date() }
    var trialUsed: Bool { trialStarted != nil }

    var isUnlocked: Bool {
        #if DEBUG
        switch override {
        case "locked": return false
        case "unlocked", "trial": return true
        default: break
        }
        #endif
        return purchased || earlyUser || inTrial
    }

    /// For the ⋯ menu and the Pro screen.
    var statusText: String {
        if purchased { return "Unlocked" }
        if earlyUser { return "Unlocked: thanks for being an early user" }
        if inTrial, let ends = trialEnds {
            let days = max(1, Calendar.current.dateComponents([.day], from: Date(), to: ends).day.map { $0 + 1 } ?? 1)
            return days == 1 ? "Trial: last day" : "Trial: \(days) days left"
        }
        #if DEBUG
        if override == "unlocked" { return "Unlocked (debug)" }
        if override == "trial" { return "Trial: 6 days left (debug)" }
        #endif
        return trialUsed ? "Trial ended" : "Try it free for \(Self.trialDays) days"
    }

    var priceText: String? { products[Self.proID]?.displayPrice }

    /// Starts listening for purchases (including ones finished on another device) and reads the
    /// current state. Called once at launch.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            await refresh()
            await loadProducts()
        }
    }

    func loadProducts() async {
        do {
            let list = try await Product.products(for: [Self.proID, Self.trialID])
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            if list.isEmpty { debugLog("pro: the App Store returned no products") }
        } catch {
            debugLog("pro: products: \(error.localizedDescription)")
        }
    }

    func refresh() async {
        var bought = false
        var trial: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.proID: bought = true
            case Self.trialID: trial = transaction.purchaseDate
            default: break
            }
        }
        purchased = bought
        trialStarted = trial
        if !bought, let result = try? await AppTransaction.shared, case .verified(let app) = result {
            earlyUser = Self.isEarlyUser(app)
        }
    }

    /// Production installs only: in TestFlight and Xcode the original version is always "1.0" or the
    /// current build, which says nothing about when someone first installed the app.
    static func isEarlyUser(_ app: AppTransaction) -> Bool {
        guard app.environment == .production else { return false }
        #if targetEnvironment(macCatalyst)
        return app.originalAppVersion.compare(firstPaidVersion, options: .numeric) == .orderedAscending
        #else
        return (Int(app.originalAppVersion) ?? .max) <= lastFreeBuild
        #endif
    }

    func buy() async { await purchase(Self.proID) }
    func startTrial() async { await purchase(Self.trialID) }

    /// "Restore purchase": asks the App Store for this Apple Account's purchases.
    func restore() async {
        busy = true
        defer { busy = false }
        message = nil
        do {
            try await AppStore.sync()
            await refresh()
            message = isUnlocked ? "Pro is unlocked." : "No Pro purchase found for this Apple Account."
        } catch {
            message = error.localizedDescription
        }
    }

    private func purchase(_ id: String) async {
        guard let product = products[id] else {
            message = "The App Store isn't answering. Check the internet connection and try again."
            await loadProducts()
            return
        }
        busy = true
        defer { busy = false }
        message = nil
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = "The App Store couldn't confirm the purchase."
                    return
                }
                await transaction.finish()
                await refresh()
            case .pending:
                message = "Waiting for approval (Ask to Buy). Pro unlocks once it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
