//
//  ReviewManager.swift
//  BitcoinWidgets
//

import Foundation

/// Tracks app launches and decides when to request an App Store review.
/// Apple's framework throttles actual prompts to max 3 per year regardless,
/// so we only need to fire at meaningful milestones.
final class ReviewManager {
    static let shared = ReviewManager()
    private init() {}

    private let defaults = UserDefaults.standard

    private enum Key {
        static let launchCount   = "review_launch_count"
        static let lastRequested = "review_last_requested"
    }

    // Milestones (launch counts) at which we try to prompt
    private let milestones: Set<Int> = [5, 20, 60]
    // Minimum days between two prompts
    private let cooldownDays = 60

    func trackAppLaunch() {
        let count = defaults.integer(forKey: Key.launchCount) + 1
        defaults.set(count, forKey: Key.launchCount)
    }

    var shouldRequest: Bool {
        let count = defaults.integer(forKey: Key.launchCount)
        guard milestones.contains(count) else { return false }

        // Cooldown guard
        if let last = defaults.object(forKey: Key.lastRequested) as? Date {
            let days = Calendar.current.dateComponents([.day], from: last, to: .now).day ?? 0
            return days >= cooldownDays
        }
        return true // Never prompted before
    }

    func markRequested() {
        defaults.set(Date(), forKey: Key.lastRequested)
    }
}
