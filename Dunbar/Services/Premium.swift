import Foundation
import SwiftData

enum Premium {
    /// Free tier: up to 10 people
    static let freeTierPersonLimit = 10
    
    /// StoreKit product identifier for premium unlock
    static let productID = "com.handbook.dunbar.premium"
    
    /// Check if the user has hit the free tier limit
    static func isAtLimit(currentCount: Int) -> Bool {
        // TODO: Check StoreKit entitlement for premium users
        return currentCount >= freeTierPersonLimit
    }
    
    /// Check if user has premium access
    static var isPremium: Bool {
        // TODO: Implement StoreKit 2 entitlement check
        // For now, always return false (free tier)
        return false
    }
}
