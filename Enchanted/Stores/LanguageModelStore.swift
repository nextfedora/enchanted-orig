//
//  ModelStore.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData

@Observable
final class LanguageModelStore {
    static let shared = LanguageModelStore(swiftDataService: SwiftDataService.shared)
    
    private var swiftDataService: SwiftDataService
    private var llamaCppService: LlamaCppService?
    private var mlxService: MLXService?
    
    @MainActor var models: [LanguageModelSD] = []
    @MainActor var supportsImages = false // This property might need re-evaluation based on selectedModel
    @MainActor var selectedModel: LanguageModelSD?
    
    init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
        
        // Initialize LlamaCppService
        if let llamaCppUrlString = UserDefaults.standard.string(forKey: "llamaCppUri"),
           !llamaCppUrlString.isEmpty,
           var llamaCppUrl = URL(string: llamaCppUrlString) {
            if llamaCppUrl.scheme == nil { // Add default scheme if missing
                llamaCppUrl = URL(string: "http://" + llamaCppUrlString) ?? llamaCppUrl
            }
            let apiKey = UserDefaults.standard.string(forKey: "llamaCppApiKey")
            self.llamaCppService = LlamaCppService(baseURL: llamaCppUrl, apiKey: apiKey)
        }
        
        // Initialize MLXService
        if let mlxUrlString = UserDefaults.standard.string(forKey: "mlxUri"),
           !mlxUrlString.isEmpty,
           var mlxUrl = URL(string: mlxUrlString) {
            if mlxUrl.scheme == nil { // Add default scheme if missing
                mlxUrl = URL(string: "http://" + mlxUrlString) ?? mlxUrl
            }
            let apiKey = UserDefaults.standard.string(forKey: "mlxApiKey")
            self.mlxService = MLXService(baseURL: mlxUrl, apiKey: apiKey)
        }
    }
    
    @MainActor
    func setModel(model: LanguageModelSD?) {
        if let model = model {
            // check if model still exists
            if models.contains(model) {
                selectedModel = model
                supportsImages = model.imageSupport
            } else if let firstModel = models.first {
                // if the selected model is not in the list anymore, select the first one
                selectedModel = firstModel
                supportsImages = firstModel.imageSupport
            } else {
                // if no models are available
                selectedModel = nil
                supportsImages = false
            }
        } else {
            // if explicitly setting to nil, or if no model was passed
            if let firstModel = models.first {
                selectedModel = firstModel
                supportsImages = firstModel.imageSupport
            } else {
                selectedModel = nil
                supportsImages = false
            }
        }
    }
    
    @MainActor
    func setModel(modelName: String) {
        if let modelToSet = models.first(where: { $0.name == modelName }) {
            setModel(model: modelToSet)
        } else if let firstModel = models.first {
            setModel(model: firstModel)
        } else {
            setModel(model: nil)
        }
    }
    
    func loadModels() async throws {
        var allRemoteModels: [LanguageModel] = []
        
        // Ollama Models
        OllamaService.shared.initEndpoint() // Ensure OllamaService is configured
        do {
            if await OllamaService.shared.reachable() {
                let ollamaModels = try await OllamaService.shared.getModels()
                allRemoteModels.append(contentsOf: ollamaModels)
            } else {
                print("Ollama service not reachable.")
            }
        } catch {
            print("Failed to load Ollama models: \(error)")
        }
        
        // Llama.cpp Models
        if let llamaService = self.llamaCppService {
            do {
                if await llamaService.reachable() {
                    let llamaModels = try await llamaService.getModels()
                    allRemoteModels.append(contentsOf: llamaModels)
                } else {
                    print("Llama.cpp service not reachable for URL: \(llamaService.baseURL)")
                }
            } catch {
                print("Failed to load Llama.cpp models from \(llamaService.baseURL): \(error)")
            }
        }
        
        // MLX Models
        if let mlxService = self.mlxService {
            do {
                if await mlxService.reachable() {
                    let mlxModels = try await mlxService.getModels()
                    allRemoteModels.append(contentsOf: mlxModels)
                } else {
                     print("MLX service not reachable for URL: \(mlxService.baseURL)")
                }
            } catch {
                print("Failed to load MLX models from \(mlxService.baseURL): \(error)")
            }
        }
        
        // Save all fetched models to SwiftData
        let modelsToSave = allRemoteModels.map { lm in
            LanguageModelSD(name: lm.name, imageSupport: lm.imageSupport, modelProvider: lm.provider)
        }
        try await swiftDataService.saveModels(models: modelsToSave)
        
        // Fetch from SwiftData and filter based on what's available remotely
        // This logic means if a model is removed from remote, it won't be loaded into `self.models`
        // but it won't be deleted from SwiftData unless explicitly handled.
        let storedModels = (try? await swiftDataService.fetchModels()) ?? []
        
        let currentSelectedModelName = await self.selectedModel?.name
        
        DispatchQueue.main.async {
            // Filter stored models: only keep those that were also found remotely
            // And assign the provider correctly from the remote model list
            let activeRemoteModelIdentifierTuples = allRemoteModels.map { ($0.name, $0.provider) }
            
            self.models = storedModels.filter { storedModel in
                activeRemoteModelIdentifierTuples.contains { $0.0 == storedModel.name && $0.1 == storedModel.modelProvider }
            }
            
            // Ensure selectedModel is still valid
            if let currentName = currentSelectedModelName, let newSelectedModel = self.models.first(where: {$0.name == currentName}) {
                self.selectedModel = newSelectedModel
                self.supportsImages = newSelectedModel.imageSupport
            } else if let firstModel = self.models.first {
                self.selectedModel = firstModel
                self.supportsImages = firstModel.imageSupport
            } else {
                self.selectedModel = nil
                self.supportsImages = false
            }
        }
    }
    
    func deleteAllModels() async throws {
        DispatchQueue.main.async {
            self.models = []
            self.selectedModel = nil
            self.supportsImages = false
        }
        try await swiftDataService.deleteModels()
    }

    public func reconfigureServicesAndReloadModels() async throws {
        // Re-initialize LlamaCppService
        if let llamaCppUrlString = UserDefaults.standard.string(forKey: "llamaCppUri"),
           !llamaCppUrlString.isEmpty,
           var llamaCppUrl = URL(string: llamaCppUrlString) {
            if llamaCppUrl.scheme == nil { // Add default scheme if missing
                llamaCppUrl = URL(string: "http://" + llamaCppUrlString) ?? llamaCppUrl
            }
            let apiKey = UserDefaults.standard.string(forKey: "llamaCppApiKey")
            self.llamaCppService = LlamaCppService(baseURL: llamaCppUrl, apiKey: apiKey)
        } else {
            self.llamaCppService = nil // Explicitly nil out if URI is missing/empty
        }
        
        // Re-initialize MLXService
        if let mlxUrlString = UserDefaults.standard.string(forKey: "mlxUri"),
           !mlxUrlString.isEmpty,
           var mlxUrl = URL(string: mlxUrlString) {
            if mlxUrl.scheme == nil { // Add default scheme if missing
                mlxUrl = URL(string: "http://" + mlxUrlString) ?? mlxUrl
            }
            let apiKey = UserDefaults.standard.string(forKey: "mlxApiKey")
            self.mlxService = MLXService(baseURL: mlxUrl, apiKey: apiKey)
        } else {
            self.mlxService = nil // Explicitly nil out if URI is missing/empty
        }
        
        // Ensure OllamaService is also up-to-date with its endpoint
        OllamaService.shared.initEndpoint()
        
        // Reload all models
        try await loadModels()
    }

    public func getService(for provider: ModelProvider) -> LLMService? {
        switch provider {
        case .ollama:
            // OllamaService.shared.initEndpoint() // Ensure it's configured, though reconfigureServicesAndReloadModels should handle this.
            return OllamaService.shared
        case .llamaCpp:
            // llamaCppService is configured during init and reconfigureServicesAndReloadModels
            return llamaCppService
        case .mlx:
            // mlxService is configured during init and reconfigureServicesAndReloadModels
            return mlxService
        // No default case needed if ModelProvider is fully covered and not expected to expand without code changes.
        // If ModelProvider could expand independently, a default case logging an error or returning nil would be good.
        }
    }
}
