#if canImport(XCTest)
import XCTest
@testable import MarsLogger

final class CaptureSchemaTests: XCTestCase {
    func testHeadersHaveStableUniqueColumns() {
        for header in [CaptureSchema.frameHeader, CaptureSchema.motionHeader] {
            let columns = header.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
            XCTAssertEqual(columns.count, Set(columns).count)
        }
    }

    func testNumbersUsePOSIXDecimalSeparator() {
        XCTAssertEqual(CaptureSchema.number(12.5), "12.5")
    }
}
#endif
