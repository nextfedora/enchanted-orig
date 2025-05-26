import Foundation

// Basic structure for OpenAI-compatible model list
struct LlamaCppModelList: Codable {
    let data: [LlamaCppModelInfo]
}

struct LlamaCppModelInfo: Codable {
    let id: String
    // Add other properties if needed, e.g., owned_by, created, etc.
}

// Basic structure for OpenAI-compatible chat completion request
struct LlamaCppChatCompletionRequest: Codable {
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
struct LlamaCppChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let role: String?
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


class LlamaCppService: LLMService {
    var providerType: ModelProvider { .llamaCpp }

    let baseURL: URL
    let apiKey: String?
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
            throw NSError(domain: "LlamaCppService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models. Status: \(statusCode). Body: \(responseBody)"])
        }

        do {
            let modelList = try JSONDecoder().decode(LlamaCppModelList.self, from: data)
            return modelList.data.map { LanguageModel(name: $0.id, provider: .llamaCpp, imageSupport: false) } // Assuming no image support for now
        } catch {
            throw NSError(domain: "LlamaCppService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to decode models list: \(error.localizedDescription)"])
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

        var fullMessages = messages.map { LlamaCppChatCompletionRequest.Message(role: $0.role, content: $0.content) }
        // Add the current user prompt as the last message if it's not already part of `messages`
        // For Llama.cpp, the prompt parameter in the function signature might be redundant if messages array is complete.
        // Assuming `messages` already contains the full history including the latest user prompt.
        // If `prompt` is a new, separate message, it should be appended:
        // fullMessages.append(LlamaCppChatCompletionRequest.Message(role: "user", content: prompt))


        let requestBody = LlamaCppChatCompletionRequest(model: model.name, messages: fullMessages)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw NSError(domain: "LlamaCppService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request body: \(error.localizedDescription)"])
        }

        return AsyncThrowingStream { continuation in
            let task = urlSession.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.finish(throwing: NSError(domain: "LlamaCppService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server."]))
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    let responseBody = String(data: data ?? Data(), encoding: .utf8) ?? "No response body"
                    continuation.finish(throwing: NSError(domain: "LlamaCppService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(httpResponse.statusCode). Body: \(responseBody)"]))
                    return
                }
                
                // This is a simplified SSE parser. A more robust one would handle various edge cases.
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
                                    let chunk = try JSONDecoder().decode(LlamaCppChatCompletionChunk.self, from: jsonData)
                                    if let content = chunk.choices.first?.delta.content {
                                        continuation.yield(content)
                                    }
                                    if chunk.choices.first?.finishReason != nil {
                                        continuation.finish()
                                        return
                                    }
                                } catch {
                                    // Might be a partial JSON object or other data; ignore for now or handle error
                                    // continuation.finish(throwing: error) // Be careful with finishing too early on parse errors
                                }
                            }
                        }
                    }
                     // If the loop finishes and we haven't received [DONE] or a finish_reason,
                    // and the connection presumably closed, we might need to finish here.
                    // However, a proper SSE client would handle the stream lifecycle more explicitly.
                    // For now, if the task completes without a specific SSE [DONE], we assume the stream is over.
                    // This might not be correct for all SSE implementations.
                    // A dataTask's completion handler indicates the entire response body has been received.
                    // For true streaming with URLSession, a delegate approach (URLSessionDataDelegate) is better for handling chunks as they arrive.
                    // Since we are in the dataTask completion block, this implies the stream has ended from the server's perspective.
                    // If no [DONE] was processed, we finish here.
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
