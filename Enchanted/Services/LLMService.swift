//
//  LLMService.swift
//  Enchanted
//
//  Created by Sweet Software on 2024-03-10.
//

import Foundation

protocol LLMService {
    var providerType: ModelProvider { get }
    func getModels() async throws -> [LanguageModel]
    func sendMessage(prompt: String, model: LanguageModel, messages: [MessageSD]) async throws -> AsyncThrowingStream<String, Error>
    func reachable() async -> Bool
}
