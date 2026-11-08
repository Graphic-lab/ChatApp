import XCTest
@testable import HeartToHeart

final class RecordingGestureTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 0)

    func testHoldRecordsUntilRelease() {
        var g = RecordingGesture()
        XCTAssertEqual(g.pressDown(at: t0), .start)
        XCTAssertEqual(g.pressUp(at: t0.addingTimeInterval(1.2)), .stop)
        XCTAssertEqual(g.state, .idle)
    }

    func testShortTapLatchesAndSecondTapStops() {
        var g = RecordingGesture()
        XCTAssertEqual(g.pressDown(at: t0), .start)
        XCTAssertNil(g.pressUp(at: t0.addingTimeInterval(0.1)))
        XCTAssertEqual(g.state, .latched)
        XCTAssertEqual(g.pressDown(at: t0.addingTimeInterval(3)), .stop)
        XCTAssertNil(g.pressUp(at: t0.addingTimeInterval(3.1)))
        XCTAssertEqual(g.state, .idle)
    }

    func testRepeatedPressDownIsIgnored() {
        var g = RecordingGesture()
        XCTAssertEqual(g.pressDown(at: t0), .start)
        XCTAssertNil(g.pressDown(at: t0.addingTimeInterval(0.05)))
    }
}

final class VoicePickerTests: XCTestCase {
    let voices = [
        VoiceCandidate(identifier: "nl-female", language: "nl-NL", isMale: false, quality: 2),
        VoiceCandidate(identifier: "nl-be-female", language: "nl-BE", isMale: false, quality: 1),
        VoiceCandidate(identifier: "nl-male", language: "nl-NL", isMale: true, quality: 1),
        VoiceCandidate(identifier: "uk-female", language: "uk-UA", isMale: false, quality: 1),
    ]

    func testGenderWinsOverQuality() {
        XCTAssertEqual(VoicePicker.pick(from: voices, language: "nl", preferredLocale: nil, gender: .male)?.identifier, "nl-male")
    }

    func testPreferredRegionWinsOverQuality() {
        XCTAssertEqual(VoicePicker.pick(from: voices, language: "nl", preferredLocale: "nl-BE", gender: .female)?.identifier, "nl-be-female")
    }

    func testFallsBackToOtherGenderWhenMissing() {
        XCTAssertEqual(VoicePicker.pick(from: voices, language: "uk", preferredLocale: nil, gender: .male)?.identifier, "uk-female")
    }

    func testNoVoiceForUnknownLanguage() {
        XCTAssertNil(VoicePicker.pick(from: voices, language: "fr", preferredLocale: nil, gender: .male))
    }
}

final class SupportTests: XCTestCase {
    func testLocaleToLanguageCode() {
        XCTAssertEqual(AppLanguage.code(forLocale: "nl-BE"), "nl")
        XCTAssertEqual(AppLanguage.code(forLocale: "uk-UA"), "uk")
    }

    func testBackendErrorsAreTranslated() {
        XCTAssertEqual(AppError.message(forText: "P0001: owner_protected"), AppError.messages["owner_protected"])
        XCTAssertEqual(AppError.message(forText: "something odd"), "Er ging iets mis. Probeer opnieuw.")
    }

    func testTimestampFormats() {
        XCTAssertNotNil(Timestamp.parse("2026-11-08T18:00:00.123456+00:00"))
        XCTAssertNotNil(Timestamp.parse("2026-11-08T18:00:00+00:00"))
        XCTAssertNotNil(Timestamp.parse("2026-11-08 18:00:00.123+00"))
    }
}
