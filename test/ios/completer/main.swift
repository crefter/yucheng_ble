import Foundation
import Combine
struct TestError: Error {}
var tokens = Set<AnyCancellable>()
for error in [false, true] {
    let c = Completer<Int>()
    let retained = c.future
    if error { c.completeError(TestError()) } else { c.complete(42) }
    for publisher in [retained, c.future] {
        var values = 0; var failures = 0
        publisher.sink(receiveCompletion: { if case .failure = $0 { failures += 1 } }, receiveValue: { value in
            precondition(value == 42); values += 1
            precondition(c.isCompleted)
            c.complete(99)
        }).store(in: &tokens)
        precondition(error ? failures == 1 && values == 0 : values == 1 && failures == 0)
    }
}
for _ in 0..<100 {
    let c = Completer<Int>()
    let publisher = c.future
    DispatchQueue.concurrentPerform(iterations: 8) { c.complete($0) }
    var values = 0
    publisher.sink(receiveCompletion: { _ in }, receiveValue: { _ in values += 1 }).store(in: &tokens)
    precondition(values == 1)
}
let timed = Completer<Int>()
var failures = 0
timed.future.sink(receiveCompletion: { if case .failure = $0 { failures += 1 } }, receiveValue: { _ in preconditionFailure() }).store(in: &tokens)
timed.setTimeout(0.01)
RunLoop.main.run(until: Date().addingTimeInterval(0.03))
timed.complete(42)
precondition(failures == 1)
let completed = Completer<Int>()
completed.setTimeout(0.01)
completed.complete(7)
RunLoop.main.run(until: Date().addingTimeInterval(0.03))
var value: Int?
completed.future.sink(receiveCompletion: { if case .failure = $0 { preconditionFailure() } }, receiveValue: { value = $0 }).store(in: &tokens)
precondition(value == 7)
print("PASS Completer replay, error, reentry, 100 concurrent completions, timeouts")
