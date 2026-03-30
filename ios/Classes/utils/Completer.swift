import Combine
import Foundation

func completer<T>(
    _ body: (Completer<T>) -> Void
) -> AnyPublisher<T, Error> {
    let c = Completer<T>()
    body(c)
    return c.future
}

final class Completer<T> {
    private let subject = PassthroughSubject<T, Error>()
    private let lock = NSRecursiveLock()
    private var result: Result<T, Error>?
    
    private var _isCompleted = false
    private var timeoutWorkItem: DispatchWorkItem?
    
    public var future: AnyPublisher<T, Error> {
        lock.withLock {
                if let result {
                    return Result.Publisher(result)
                        .eraseToAnyPublisher()
                } else {
                    return subject.eraseToAnyPublisher()
                }
            }
    }
    
    public var isCompleted: Bool {
        lock.withLock { _isCompleted }
    }
    
    // MARK: - Completion
    
    public func complete(_ value: T) {
        guard !markAsCompleted() else { return }
        
        lock.withLock {
                result = .success(value)
        }
        
        cancelTimeout()
        subject.send(value)
        subject.send(completion: .finished)
    }
    
    public func completeError(_ error: Error) {
        guard !markAsCompleted() else { return }
        
        lock.withLock {
            result = .failure(error)
        }
        
        cancelTimeout()
        subject.send(completion: .failure(error))
    }
    
    // MARK: - Timeout
    
    public func setTimeout(
        _ interval: TimeInterval,
        queue: DispatchQueue = .main,
        error: Error = TimeoutError()
    ) {
        lock.withLock {
            guard !_isCompleted else { return }
            
            timeoutWorkItem?.cancel()
            
            let workItem = DispatchWorkItem { [weak self] in
                self?.completeError(error)
            }
            
            timeoutWorkItem = workItem
            queue.asyncAfter(deadline: .now() + interval, execute: workItem)
        }
    }
    
    private func cancelTimeout() {
        lock.withLock {
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
        }
    }
    
    // MARK: - Internal
    
    private func markAsCompleted() -> Bool {
        lock.withLock {
            guard !_isCompleted else {
                debugPrint("⚠️ Completer already completed")
                return true
            }
            _isCompleted = true
            return false
        }
    }
    
    deinit {
        cancelTimeout()
        assert(isCompleted, "Completer deinit without completion")
    }
}

// MARK: - Timeout Error

struct TimeoutError: Error, LocalizedError {
    var errorDescription: String? {
        "Operation timed out"
    }
}
