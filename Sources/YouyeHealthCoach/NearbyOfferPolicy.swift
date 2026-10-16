import Foundation

/// Categories are deliberately separate: an owner can want a swim offer alert without ever
/// opting into delivery or grocery alerts. This is a preference contract, not a background task.
public enum NearbyOfferKind: String, Codable, Sendable, CaseIterable, Equatable {
    case gym
    case swimming
    case sharedBike
    case grocery
    case delivery

    public var displayName: String {
        switch self {
        case .gym: "健身房"
        case .swimming: "游泳"
        case .sharedBike: "共享单车"
        case .grocery: "食材/商超"
        case .delivery: "外卖"
        }
    }
}

/// Builds only the owner-visible Maps handoff used by the nearby-place screen. It neither starts
/// a search nor requests location: opening the resulting link remains a separate tap in UI.
/// The coarse-area guard is repeated here so a malformed restored profile cannot put a precise
/// address into a system handoff.
public enum NearbyPlaceSearchLink {
    public static func mapsURL(
        for kind: NearbyOfferKind,
        approximateArea: String?,
        currentLocation: NearbyMapCoordinate? = nil
    ) -> URL? {
        let keyword: String
        switch kind {
        case .gym: keyword = "健身房"
        case .swimming: keyword = "游泳馆"
        case .sharedBike: keyword = "共享单车"
        case .grocery: keyword = "生鲜超市"
        case .delivery: return nil
        }
        let normalizedArea = ApproximateAreaPolicy.normalized(approximateArea ?? "")
        let safeArea = ApproximateAreaPolicy.validationError(for: normalizedArea) == nil ? normalizedArea : nil
        // A fresh owner-requested location is the map-search centre of record.  Keeping an old
        // profile area inside the text query would make a travel-day search appear nearby while
        // still returning the old neighbourhood. The typed fuzzy area remains the deliberate
        // fallback when location is unavailable or declined.
        let query = currentLocation == nil && safeArea?.isEmpty == false ? "\(safeArea!) \(keyword)" : keyword
        // Apple Maps' universal link is more reliable than the custom `maps:` scheme in iPhone
        // Mirroring. It is still opened only after the owner taps the visible handoff button.
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        var queryItems = [URLQueryItem(name: "q", value: query)]
        if let currentLocation {
            // Coordinates are deliberately rounded before they leave the process.  They are a
            // short-lived map-search centre, never a saved home/work address or a background
            // location feed.
            queryItems.append(URLQueryItem(name: "ll", value: currentLocation.mapsQueryValue))
        }
        components.queryItems = queryItems
        return components.url
    }
}

/// A coarse, one-off centre for an owner-initiated Apple Maps handoff.  Rounding to about 100 m
/// gives nearby results without retaining an exact device coordinate in the app's private data.
public struct NearbyMapCoordinate: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude) else { return nil }
        self.latitude = (latitude * 1_000).rounded() / 1_000
        self.longitude = (longitude * 1_000).rounded() / 1_000
    }

    fileprivate var mapsQueryValue: String {
        String(format: "%.3f,%.3f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
}

/// The minimum evidence a future authorized provider must return before an offer can become an
/// in-app alert. It intentionally does not include a home address, coordinate, account, or any
/// purchase action. URLs are treated as display provenance, never fetched by this value type.
public struct VerifiedNearbyOffer: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: NearbyOfferKind
    public let title: String
    public let nearbyPlace: String
    public let sourceName: String
    public let checkedAt: Date
    public let validUntil: Date?
    public let terms: String
    public let priceYuan: Decimal?
    public let basketSavingsYuan: Decimal?

    public init(
        id: UUID = UUID(),
        kind: NearbyOfferKind,
        title: String,
        nearbyPlace: String,
        sourceName: String,
        checkedAt: Date,
        validUntil: Date? = nil,
        terms: String,
        priceYuan: Decimal? = nil,
        basketSavingsYuan: Decimal? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.nearbyPlace = nearbyPlace
        self.sourceName = sourceName
        self.checkedAt = checkedAt
        self.validUntil = validUntil
        self.terms = terms
        self.priceYuan = priceYuan
        self.basketSavingsYuan = basketSavingsYuan
    }
}

public enum NearbyOfferPresentation: Sendable, Equatable {
    case awaitingProvider
    case explicitRequestRequired
    case preferenceDisabled
    case missingEvidence
    case stale
    case belowThreshold
    case eligible

    public var displayText: String {
        switch self {
        case .awaitingProvider: "附近优惠服务尚未连接；不查实时价格、不发送通知。当前位置仅在你主动更新地图时临时使用。"
        case .explicitRequestRequired: "需由你在当次主动发起附近搜索；外卖还需单独明确请求，不提醒。"
        case .preferenceDisabled: "你没有开启这一类优惠提醒。"
        case .missingEvidence: "待核验：缺少来源、检查时间、地点或适用条件，不提醒。"
        case .stale: "待核验：优惠检查时间已过期，不提醒。"
        case .belowThreshold: "已核验，但未达到你设置的特别优惠阈值。"
        case .eligible: "已核验且达到你的提醒阈值；仍需由你自行查看和决定。"
        }
    }
}

/// A saved preference is never permission to look up a place in the background.  The caller must
/// carry the interaction that produced a future provider result into this policy. Delivery has a
/// stricter boundary than other categories: its result is usable only for the particular request
/// in which the owner explicitly asked for delivery choices.
public enum NearbyOfferRequestContext: Sendable, Equatable {
    /// No owner action is attached (including background refresh, an imported value, or a stale
    /// view). Nothing may become eligible in this state.
    case unspecified
    /// The owner has just chosen a coarse search place and asked to check a non-delivery category.
    case ownerInitiatedNearbySearch
    /// The owner has specifically asked to inspect delivery options in this interaction.
    case explicitDeliveryRequest

    fileprivate func authorizes(_ kind: NearbyOfferKind) -> Bool {
        switch (self, kind) {
        case (.ownerInitiatedNearbySearch, .gym),
             (.ownerInitiatedNearbySearch, .swimming),
             (.ownerInitiatedNearbySearch, .sharedBike),
             (.ownerInitiatedNearbySearch, .grocery),
             (.explicitDeliveryRequest, .delivery):
            true
        default:
            false
        }
    }
}

/// A non-networking gate for future provider responses. The app must call this after, not before,
/// a user has voluntarily chosen a search place and the provider has returned verifiable evidence.
/// This policy never performs location lookup, scraping, notification scheduling, coupon claiming,
/// ordering, payment, or sharing.
public enum NearbyOfferPolicy {
    public static let maximumFreshness: TimeInterval = 60 * 60

    public static func presentation(
        for offer: VerifiedNearbyOffer?,
        preferences: NearbyOfferPreferences,
        requestContext: NearbyOfferRequestContext = .unspecified,
        now: Date = .now
    ) -> NearbyOfferPresentation {
        guard let offer else { return .awaitingProvider }
        guard requestContext.authorizes(offer.kind) else { return .explicitRequestRequired }
        guard isEnabled(offer.kind, preferences: preferences) else { return .preferenceDisabled }
        guard isEvidenceComplete(offer) else { return .missingEvidence }
        // A provider timestamp in the future is not fresh evidence. Treating a negative
        // interval as "within one hour" would let a malformed or clock-skewed result trigger
        // an alert before it was actually checked.
        guard offer.checkedAt <= now,
              now.timeIntervalSince(offer.checkedAt) <= maximumFreshness,
              offer.validUntil.map({ $0 >= now && $0 >= offer.checkedAt }) ?? true else { return .stale }
        guard reachesThreshold(offer, preferences: preferences) else { return .belowThreshold }
        return .eligible
    }

    private static func isEnabled(_ kind: NearbyOfferKind, preferences: NearbyOfferPreferences) -> Bool {
        switch kind {
        case .gym: preferences.gymRemindersEnabled
        case .swimming: preferences.swimmingRemindersEnabled
        case .sharedBike: preferences.bikeRemindersEnabled
        case .grocery: preferences.groceryRemindersEnabled
        case .delivery: preferences.deliveryRemindersEnabled
        }
    }

    private static func isEvidenceComplete(_ offer: VerifiedNearbyOffer) -> Bool {
        !offer.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !offer.nearbyPlace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !offer.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !offer.terms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func reachesThreshold(_ offer: VerifiedNearbyOffer, preferences: NearbyOfferPreferences) -> Bool {
        switch offer.kind {
        case .grocery, .delivery:
            guard let savings = offer.basketSavingsYuan, savings.isFinite, savings >= 0 else { return false }
            return savings >= Decimal(preferences.basketSavingsThresholdYuan)
        case .swimming:
            guard let price = offer.priceYuan, price.isFinite, price >= 0 else { return false }
            return price <= Decimal(preferences.swimSingleEntryThresholdYuan)
        case .gym, .sharedBike:
            // An eventual product rule can add an owner-selected threshold for each. Until then,
            // no alert is allowed merely because a price happened to be returned.
            return false
        }
    }
}
