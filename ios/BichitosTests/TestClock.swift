import Foundation
@testable import Bichitos

/// No test depends on the runner's clock: worlds start at a fixed date in a fixed zone, by daylight unless a test says otherwise.
extension World {
    static let testStart = Date(timeIntervalSince1970: 1_700_000_000) // 22:13 UTC
    /// UTC−10, where `testStart` is 12:13.
    static let daytime = TimeZone(secondsFromGMT: -10 * 3600)!

    init(testSeed seed: UInt64, date: Date = World.testStart, timeZone: TimeZone = World.daytime) {
        self.init(seed: seed, date: date)
        self.timeZone = timeZone
    }
}
