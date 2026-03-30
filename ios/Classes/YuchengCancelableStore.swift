//
//  YuchengCancelableStore.swift
//  Pods
//
//  Created by Maxim Zarechnev on 20.03.2026.
//

import Foundation
import Combine

class YuchengCancelableStore {
    static let shared = YuchengCancelableStore()
    private var subscriptions: [UUID: AnyCancellable] = [:]
    
    private init() {}

    func subscribe<T>(_ publisher: AnyPublisher<T, Error>, receiveCompletion: @escaping (Subscribers.Completion<Error>) -> Void, receiveValue: @escaping (T) -> Void) {
        let id = UUID()
        
        subscriptions[id] = publisher
            .sink(
                receiveCompletion: { [weak self] received in
                    receiveCompletion(received)
                    self?.subscriptions[id] = nil
                },
                receiveValue: { value in
                    receiveValue(value)
                    print(value)
                }
            )
    }
}
