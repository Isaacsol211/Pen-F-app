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
///   free, keeps Pro;
/// - testing in TestFlight while the App Store has no Pro product yet (before the in-app purchases are
///   set up in App Store Connect), so testers can try the Pro tools. Once the products exist, testers
///   go through the real trial and purchase in the sandbox.
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
    /// The App Store answered the products request (with or without products).
    private(set) var productsLoaded = false
    /// Where this copy came from: production, sandbox (TestFlight) or Xcode.
    private(set) var environment: AppStore.Environment?
    private(set) var busy = false
    var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?
    #if DEBUG
    /// Builds from Xcode or the Mac have Pro unlocked. `-pro locked|trial` pins a state to try the
    /// locks and the Pro screen; `-pro store` uses the App Store logic (e.g. with Shutterlink.storekit).
    @ObservationIgnored private let override = UserDefaults.standard.string(forKey: "pro")
    #endif

    var trialEnds: Date? {
        trialStarted.flatMap { Calendar.current.date(byAdding: .day, value: Self.trialDays, to: $0) }
    }
    var inTrial: Bool { (trialEnds ?? .distantPast) > Date() }
    var trialUsed: Bool { trialStarted != nil }

    /// TestFlight before the Pro product exists in App Store Connect. Where the app came from and what
    /// the App Store last said are remembered, because the App Store can't be reached while the phone
    /// is on a camera's Wi-Fi; until it has said there is a Pro product, testers have Pro.
    var testerUnlock: Bool {
        let source = environment ?? UserDefaults.standard.string(forKey: Self.environmentKey).map { AppStore.Environment(rawValue: $0) }
        guard source == .sandbox else { return false }
        if productsLoaded { return products[Self.proID] == nil }
        return UserDefaults.standard.object(forKey: Self.testerKey) as? Bool ?? true
    }
    private static let testerKey = "pro.testerUnlock"
    private static let environmentKey = "pro.environment"

    var isUnlocked: Bool {
        #if DEBUG
        switch override {
        case "locked": return false
        case "store": break
        default: return true
        }
        #endif
        return purchased || earlyUser || inTrial || testerUnlock
    }

    /// For the ⋯ menu and the Pro screen.
    var statusText: String {
        #if DEBUG
        switch override {
        case "trial": return "Trial: 6 days left (debug)"
        case "locked", "store": break
        default: return "Unlocked (developer build)"
        }
        #endif
        if purchased { return "Unlocked" }
        if earlyUser { return "Unlocked: thanks for being an early user" }
        if testerUnlock { return "Unlocked for TestFlight testing" }
        if inTrial, let ends = trialEnds {
            let days = max(1, Calendar.current.dateComponents([.day], from: Date(), to: ends).day.map { $0 + 1 } ?? 1)
            return days == 1 ? "Trial: last day" : "Trial: \(days) days left"
        }
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
            productsLoaded = true
            if environment == .sandbox { UserDefaults.standard.set(products[Self.proID] == nil, forKey: Self.testerKey) }
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
        if let result = try? await AppTransaction.shared {
            // An unverified one still says where the app came from; early-user status needs a verified one.
            environment = result.unsafePayloadValue.environment
            UserDefaults.standard.set(environment?.rawValue, forKey: Self.environmentKey)
            if case .verified(let app) = result, !bought { earlyUser = Self.isEarlyUser(app) }
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
            default: break   // the user cancelled
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
