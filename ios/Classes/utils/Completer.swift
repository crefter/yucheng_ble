import Combine
import Foundation

func completer<T>(_ body: (Completer<T>) -> Void) -> AnyPublisher<T, Error> {
    let c = Completer<T>()
    body(c)
    return c.future
}

final class Completer<T> {
    private let lock = NSLock()
    private let publisher: AnyPublisher<T, Error>
    private let resolve: Future<T, Error>.Promise
    private var completed = false
    private var timeoutWorkItem: DispatchWorkItem?

    init() {
        var promise: Future<T, Error>.Promise!
        let future = Future<T, Error> { promise = $0 }
        publisher = future.eraseToAnyPublisher()
        resolve = promise
    }

    // Future сохраняет ответ, в том числе между получением publisher и sink.
    var future: AnyPublisher<T, Error> { publisher }
    var isCompleted: Bool { lock.withLock { completed } }

    func complete(_ value: T) { finish(.success(value)) }
    func completeError(_ error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<T, Error>) {
        let claimed = lock.withLock {
            guard !completed else { return false }
            completed = true
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            return true
        }
        // Подписчики могут повторно обратиться к Completer: вызываем их без lock.
        if claimed { resolve(result) }
    }

    func setTimeout(_ interval: TimeInterval, queue: DispatchQueue = .main,
                    error: Error = TimeoutError()) {
        lock.withLock {
            guard !completed else { return }
            timeoutWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.completeError(error) }
            timeoutWorkItem = work
            queue.asyncAfter(deadline: .now() + interval, execute: work)
        }
    }

    deinit { timeoutWorkItem?.cancel() }
}

struct TimeoutError: Error, LocalizedError {
    var errorDescription: String? { "Operation timed out" }
}
