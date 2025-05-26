import Foundation

// Basic structure for OpenAI-compatible model list
struct MLXModelList: Codable {
    let data: [MLXModelInfo]
}

struct MLXModelInfo: Codable {
    let id: String
    // Add other properties if needed, e.g., owned_by, created, etc.
}

// Basic structure for OpenAI-compatible chat completion request
struct MLXChatCompletionRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let stream: Bool = true
    // Add other parameters like temperature, max_tokens etc. if needed
}

// Basic structure for OpenAI-compatible chat completion stream chunk
struct MLXChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let role: String? // Role might appear in the first chunk
        }
        let delta: Delta
        let finishReason: String? // "stop", "length", etc.
    }
    let id: String?
    let model: String?
    let choices: [Choice]
    let created: Int?
    let object: String? // e.g. "chat.completion.chunk"
}


class MLXService: LLMService {
    var providerType: ModelProvider { .mlx }

    let baseURL: URL
    let apiKey: String? // MLX might not use API keys by default
    private let urlSession: URLSession

    init(baseURL: URL, apiKey: String? = nil, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func getModels() async throws -> [LanguageModel] {
        let url = baseURL.appendingPathComponent("/v1/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw NSError(domain: "MLXService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models. Status: \(statusCode). Body: \(responseBody)"])
        }

        do {
            let modelList = try JSONDecoder().decode(MLXModelList.self, from: data)
            return modelList.data.map { LanguageModel(name: $0.id, provider: .mlx, imageSupport: false) } // Assuming no image support
        } catch {
            throw NSError(domain: "MLXService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to decode models list: \(error.localizedDescription)"])
        }
    }

    func sendMessage(prompt: String, model: LanguageModel, messages: [MessageSD]) async throws -> AsyncThrowingStream<String, Error> {
        let url = baseURL.appendingPathComponent("/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Combine existing messages with the new prompt.
        // Assuming `messages` contains the history and `prompt` is the latest user message.
        // If `messages` already includes the latest prompt, this logic might need adjustment
        // based on how MessageSD and the overall chat flow are structured.
        var fullMessages = messages.map { MLXChatCompletionRequest.Message(role: $0.role, content: $0.content) }
        if !prompt.isEmpty { // Add the current prompt as the last user message if it's not empty
             //This check ensures we don't add an empty user message if prompt is just for satisfying the old protocol but messages array is complete.
            if fullMessages.last?.role != "user" || fullMessages.last?.content != prompt {
                 fullMessages.append(MLXChatCompletionRequest.Message(role: "user", content: prompt))
            }
        }


        let requestBody = MLXChatCompletionRequest(model: model.name, messages: fullMessages)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw NSError(domain: "MLXService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request body: \(error.localizedDescription)"])
        }

        return AsyncThrowingStream { continuation in
            let task = urlSession.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.finish(throwing: NSError(domain: "MLXService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server."]))
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    let responseBody = String(data: data ?? Data(), encoding: .utf8) ?? "No response body"
                    continuation.finish(throwing: NSError(domain: "MLXService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(httpResponse.statusCode). Body: \(responseBody)"]))
                    return
                }
                
                // Simplified SSE parser
                if let data = data {
                    let stringData = String(data: data, encoding: .utf8) ?? ""
                    let lines = stringData.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    
                    for line in lines {
                        if line.hasPrefix("data: ") {
                            let jsonDataString = String(line.dropFirst(6))
                            if jsonDataString == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            if let jsonData = jsonDataString.data(using: .utf8) {
                                do {
                                    let chunk = try JSONDecoder().decode(MLXChatCompletionChunk.self, from: jsonData)
                                    if let content = chunk.choices.first?.delta.content {
                                        continuation.yield(content)
                                    }
                                    if chunk.choices.first?.finishReason != nil {
                                        continuation.finish()
                                        return
                                    }
                                } catch {
                                    // Ignoring errors for partial JSON objects for now
                                }
                            }
                        }
                    }
                    // If dataTask completion block is called, it means the full response body has been received.
                    // If [DONE] was not explicitly found, finish the stream.
                    continuation.finish()
                } else {
                     continuation.finish()
                }
            }
            task.resume()
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func reachable() async -> Bool {
        do {
            _ = try await getModels()
            return true
        } catch {
            return false
        }
    }
}
