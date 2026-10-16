import XCTest
@testable import Sajda

final class PauseChallengeTests: XCTestCase {
    func testPlanHasTenRoundsAndEveryKind() {
        var rng = SeededGenerator(seed: 42)

        let plan = ChallengeGenerator.plan(rounds: PauseChallenge.rounds, using: &rng)

        XCTAssertEqual(plan.count, 10)
        for kind in ChallengeTask.Kind.allCases {
            XCTAssertTrue(plan.contains(kind), "missing \(kind)")
        }
    }

    func testMistakeSendsBackTwoRoundsButNotBelowZero() {
        var challenge = PauseChallenge()
        challenge.registerFailure()
        XCTAssertEqual(challenge.completed, 0)

        (0..<5).forEach { _ in challenge.registerSuccess() }
        challenge.registerFailure()

        XCTAssertEqual(challenge.completed, 3)
        XCTAssertEqual(challenge.mistakes, 2)
        XCTAssertFalse(challenge.isFinished)
    }

    func testFinishesAfterTenSuccesses() {
        var challenge = PauseChallenge()
        (0..<12).forEach { _ in challenge.registerSuccess() }
        XCTAssertTrue(challenge.isFinished)
        XCTAssertEqual(challenge.completed, PauseChallenge.rounds)
    }

    func testMathAnswersArePositiveAndChecked() {
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<300 {
            guard case .math(_, let answer) = ChallengeGenerator.make(.math, using: &rng) else {
                return XCTFail("expected math")
            }
            XCTAssertGreaterThan(answer, 0)
            let task = ChallengeTask.math(question: "", answer: answer)
            XCTAssertTrue(task.accepts(" \(answer) "))
            XCTAssertFalse(task.accepts("\(answer + 1)"))
        }
    }

    func testCodeAndMemoryAnswersIgnoreCaseAndSpaces() {
        XCTAssertTrue(ChallengeTask.code("K7Q M2X").accepts("k7qm2x"))
        XCTAssertTrue(ChallengeTask.code("K7Q M2X").accepts("K7Q-M2X"))
        XCTAssertFalse(ChallengeTask.code("K7Q M2X").accepts("K7QM2Y"))
        XCTAssertTrue(ChallengeTask.memory(digits: "031945").accepts("031 945"))
        XCTAssertFalse(ChallengeTask.memory(digits: "031945").accepts("31945"))
    }

    func testOddOneOutHasExactlyOneDifferentSymbol() {
        var rng = SeededGenerator(seed: 3)
        guard case .oddOneOut(let symbols, let odd) = ChallengeGenerator.make(.oddOneOut, using: &rng) else {
            return XCTFail("expected oddOneOut")
        }
        XCTAssertEqual(symbols.count, ChallengeGenerator.oddGridSize)
        XCTAssertEqual(symbols.filter { $0 == symbols[odd] }.count, 1)
        XCTAssertTrue(ChallengeTask.oddOneOut(symbols: symbols, oddIndex: odd).accepts(index: odd))
    }

    func testStroopInkDiffersFromWordAndIsAnOption() {
        var rng = SeededGenerator(seed: 11)
        for _ in 0..<50 {
            guard case .stroop(let word, let ink, let options) = ChallengeGenerator.make(.stroop, using: &rng) else {
                return XCTFail("expected stroop")
            }
            XCTAssertNotEqual(word, ink)
            XCTAssertTrue(options.contains(ink))
            XCTAssertEqual(Set(options).count, 4)
        }
    }

    func testOrderUsesAllNumbers() {
        var rng = SeededGenerator(seed: 5)
        guard case .order(let numbers) = ChallengeGenerator.make(.order, using: &rng) else {
            return XCTFail("expected order")
        }
        XCTAssertEqual(numbers.sorted(), Array(1...ChallengeGenerator.orderCount))
    }

    func testActivePauseExpires() {
        let now = Date()
        let settings = AppSettings().with { $0.pausedUntil = now.addingTimeInterval(60) }
        XCTAssertNotNil(settings.activePause(now: now))
        XCTAssertNil(settings.activePause(now: now.addingTimeInterval(61)))
    }
}
