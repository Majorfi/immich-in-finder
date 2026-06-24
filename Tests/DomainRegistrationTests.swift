import XCTest

// DomainManager.register()'s self-heal control flow is extracted into the pure
// DomainRegistration.register helper so it can be exercised without an actual
// NSFileProviderManager (which can't run in a unit-test process). These tests
// pin the try -> try? removeAll -> retry-add behavior the App relies on.
final class DomainRegistrationTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case first
        case second
        case removeAll
    }

    // Mutable counters captured by the non-escaping closures; wrapped in a final
    // class so Swift 6 strict concurrency is happy passing them across the awaits.
    private final class Counters {
        var addCalls = 0
        var removeAllCalls = 0
    }

    func testSucceedsOnFirstTryWithoutRemovingDomains() async throws {
        let c = Counters()
        try await DomainRegistration.register(
            add: { c.addCalls += 1 },
            removeAll: { c.removeAllCalls += 1 }
        )
        XCTAssertEqual(c.addCalls, 1)
        XCTAssertEqual(c.removeAllCalls, 0)
    }

    func testFailThenRecoverClearsOnceAndRetries() async throws {
        let c = Counters()
        try await DomainRegistration.register(
            add: {
                c.addCalls += 1
                if c.addCalls == 1 { throw TestError.first }
            },
            removeAll: { c.removeAllCalls += 1 }
        )
        XCTAssertEqual(c.addCalls, 2)
        XCTAssertEqual(c.removeAllCalls, 1)
    }

    func testFailTwicePropagatesSecondError() async {
        let c = Counters()
        do {
            try await DomainRegistration.register(
                add: {
                    c.addCalls += 1
                    let next: TestError = if c.addCalls == 1 { .first } else { .second }
                    throw next
                },
                removeAll: { c.removeAllCalls += 1 }
            )
            XCTFail("expected the second add's error to propagate")
        } catch let error as TestError {
            XCTAssertEqual(error, .second, "the second add's error must propagate")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
        XCTAssertEqual(c.addCalls, 2)
        XCTAssertEqual(c.removeAllCalls, 1)
    }

    // removeAll throwing must not mask the retry: the `try?` swallows it, the
    // second add runs and succeeds, so no error escapes.
    func testRemoveAllThrowingDoesNotMaskSuccessfulRetry() async throws {
        let c = Counters()
        try await DomainRegistration.register(
            add: {
                c.addCalls += 1
                if c.addCalls == 1 { throw TestError.first }
            },
            removeAll: {
                c.removeAllCalls += 1
                throw TestError.removeAll
            }
        )
        XCTAssertEqual(c.addCalls, 2)
        XCTAssertEqual(c.removeAllCalls, 1)
    }
}
