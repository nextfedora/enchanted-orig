//
//  OllamaService.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 09/12/2023.
//

import Foundation
import OllamaKit

class OllamaService: LLMService, @unchecked Sendable {
    static let shared = OllamaService()
    
    var providerType: ModelProvider { .ollama }
    
    var ollamaKit: OllamaKit
    
    init() {
        ollamaKit = OllamaKit(baseURL: URL(string: "http://localhost:11434")!)
        initEndpoint()
    }
    
    func sendMessage(prompt: String, model: LanguageModel, messages: [MessageSD]) async throws -> AsyncThrowingStream<String, Error> {
        let ollamaMessages = messages.map { msg -> OKMessage in
            var role: OKChatRequestData.Message.Role
            switch msg.role {
            case "user":
                role = .user
            case "assistant":
                role = .assistant
            case "system":
                role = .system
            default:
                role = .user
            }
            return OKMessage(role: role, content: msg.content)
        }
        
        let request = OKChatRequestData(model: model.name, messages: ollamaMessages)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await streamResponse in ollamaKit.chat(data: request) {
                        continuation.yield(streamResponse.message?.content ?? "")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func initEndpoint(url: String? = nil, bearerToken: String? = "okki") {
        let defaultUrl = "http://localhost:11434"
        let localStorageUrl = UserDefaults.standard.string(forKey: "ollamaUri")
        let bearerToken = UserDefaults.standard.string(forKey: "ollamaBearerToken")
        if var ollamaUrl = [localStorageUrl, defaultUrl].compactMap({$0}).filter({$0.count > 0}).first {
            if !ollamaUrl.contains("http") {
                ollamaUrl = "http://" + ollamaUrl
            }
            
            if let url = URL(string: ollamaUrl) {
                ollamaKit =  OllamaKit(baseURL: url, bearerToken: bearerToken)
                return
            }
        }
    }
    
    func getModels() async throws -> [LanguageModel]  {
        let response = try await ollamaKit.models()
        let models = response.models.map {
            LanguageModel(
                name: $0.name,
                provider: .ollama,
                imageSupport: $0.details.families?.contains(where: { $0 == "clip" || $0 == "mllama" }) ?? false
            )
        }
        return models
    }
    
    func reachable() async -> Bool {
        return await ollamaKit.reachable()
    }
}
