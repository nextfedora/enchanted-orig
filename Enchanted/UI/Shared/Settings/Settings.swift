//
//  Settings.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 28/12/2023.
//

import SwiftUI
import Combine

struct Settings: View {
    var languageModelStore = LanguageModelStore.shared
    var conversationStore = ConversationStore.shared
    var swiftDataService = SwiftDataService.shared
    
    @AppStorage("selectedProvider") private var selectedProvider: ModelProvider = .ollama
    @AppStorage("ollamaUri") private var ollamaUri: String = ""
    @AppStorage("ollamaBearerToken") private var ollamaBearerToken: String = ""
    @AppStorage("llamaCppUri") private var llamaCppUri: String = ""
    @AppStorage("llamaCppApiKey") private var llamaCppApiKey: String = ""
    @AppStorage("mlxUri") private var mlxUri: String = ""
    @AppStorage("mlxApiKey") private var mlxApiKey: String = ""
    
    @AppStorage("systemPrompt") private var systemPrompt: String = ""
    @AppStorage("vibrations") private var vibrations: Bool = true
    @AppStorage("colorScheme") private var colorScheme = AppColorScheme.system
    @AppStorage("defaultModelName") private var defaultModelName: String = ""
    @AppStorage("appUserInitials") private var appUserInitials: String = ""
    @AppStorage("pingInterval") private var pingInterval: String = "5" // This might become provider-specific
    @AppStorage("voiceIdentifier") private var voiceIdentifier: String = ""
    
    @StateObject private var speechSynthesiser = SpeechSynthesizer.shared
    
    @Environment(\.presentationMode) var presentationMode
    
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var cancellable: AnyCancellable?
    
    @State var currentServerStatus: Bool? // Renamed from ollamaStatus
    
    private func save() {
        // remove trailing slash
        if ollamaUri.last == "/" {
            ollamaUri = String(ollamaUri.dropLast())
        }
        if llamaCppUri.last == "/" {
            llamaCppUri = String(llamaCppUri.dropLast())
        }
        if mlxUri.last == "/" {
            mlxUri = String(mlxUri.dropLast())
        }
        
        // Re-initialize or re-configure services in LanguageModelStore.
        // Forcing re-initialization of the store might be too broad.
        // A dedicated method in LanguageModelStore to reconfigure services would be cleaner.
        // For now, re-creating the store instance to trigger its init which reads UserDefaults.
        // This is a simplified approach; a more robust solution would involve a dedicated method in LanguageModelStore.
        LanguageModelStore.shared = LanguageModelStore(swiftDataService: SwiftDataService.shared)
        
        Task {
            Haptics.shared.mediumTap()
            try? await languageModelStore.loadModels()
            // Update the default model for the currently selected provider
            languageModelStore.setModel(modelName: defaultModelName)
        }
        presentationMode.wrappedValue.dismiss()
    }
    
    private func checkServer() {
        Task {
            var service: LLMService?
            var reachable = false
            
            // Ensure URIs are up-to-date for the check
            let currentOllamaUri = ollamaUri
            let currentOllamaToken = ollamaBearerToken
            let currentLlamaCppUri = llamaCppUri
            let currentLlamaCppToken = llamaCppApiKey
            let currentMlxUri = mlxUri
            let currentMlxToken = mlxApiKey

            switch selectedProvider {
            case .ollama:
                OllamaService.shared.initEndpoint(url: currentOllamaUri, bearerToken: currentOllamaToken)
                service = OllamaService.shared
            case .llamaCpp:
                if var url = URL(string: currentLlamaCppUri) {
                    if url.scheme == nil { url = URL(string: "http://" + currentLlamaCppUri) ?? url }
                    service = LlamaCppService(baseURL: url, apiKey: currentLlamaCppToken)
                }
            case .mlx:
                if var url = URL(string: currentMlxUri) {
                    if url.scheme == nil { url = URL(string: "http://" + currentMlxUri) ?? url }
                    service = MLXService(baseURL: url, apiKey: currentMlxToken)
                }
            }
            
            if let service = service {
                reachable = await service.reachable()
            }
            
            DispatchQueue.main.async {
                self.currentServerStatus = reachable
            }
            
            if reachable {
                // Reload models for all providers to ensure consistency,
                // especially if this checkServer is also used after changing provider.
                try? await languageModelStore.loadModels()
            }
        }
    }
    
    private func deleteAll() {
        Task {
            try? await conversationStore.deleteAllConversations()
            try? await languageModelStore.deleteAllModels()
            DispatchQueue.main.async {
                defaultModelName = "" // Clear default model as well
            }
        }
    }
    
    var currentProviderLanguageModels: [LanguageModelSD] {
        languageModelStore.models.filter { $0.modelProvider == selectedProvider }
    }
    
    var body: some View {
        SettingsView(
            selectedProvider: $selectedProvider,
            ollamaUri: $ollamaUri,
            ollamaBearerToken: $ollamaBearerToken,
            llamaCppUri: $llamaCppUri,
            llamaCppApiKey: $llamaCppApiKey,
            mlxUri: $mlxUri,
            mlxApiKey: $mlxApiKey,
            systemPrompt: $systemPrompt,
            vibrations: $vibrations,
            colorScheme: $colorScheme,
            defaultModelName: $defaultModelName,
            appUserInitials: $appUserInitials,
            pingInterval: $pingInterval,
            voiceIdentifier: $voiceIdentifier,
            currentServerStatus: $currentServerStatus,
            save: save,
            checkServer: checkServer,
            deleteAll: deleteAll,
            currentProviderLanguageModels: currentProviderLanguageModels,
            voices: speechSynthesiser.voices
        )
        .frame(maxWidth: 700)
#if os(visionOS)
        .frame(minWidth: 600, minHeight: 800)
#endif
        .onChange(of: defaultModelName) { _, modelName in
            // This ensures that if the user changes the default model in settings,
            // it's actually applied to the store's selectedModel, but only for the current provider.
            if let modelToSet = currentProviderLanguageModels.first(where: { $0.name == modelName }) {
                languageModelStore.setModel(model: modelToSet)
            } else if let firstModel = currentProviderLanguageModels.first {
                // if the specific model name isn't found (e.g. after provider switch), pick the first available for this provider
                defaultModelName = firstModel.name // Update AppStorage
                languageModelStore.setModel(model: firstModel)
            } else {
                 defaultModelName = "" // No models for this provider
                 languageModelStore.setModel(model: nil)
            }
        }
        .onChange(of: selectedProvider) { _, newProvider in
            // When provider changes, update the default model to the first model of the new provider
            // or clear it if no models are available for the new provider.
            // Also, trigger a server check for the new provider.
            currentServerStatus = nil // Reset status
            checkServer() // Check new provider's server status
            if let firstModel = languageModelStore.models.filter({ $0.modelProvider == newProvider }).first {
                defaultModelName = firstModel.name
                languageModelStore.setModel(model: firstModel)
            } else {
                defaultModelName = ""
                languageModelStore.setModel(model: nil)
            }
        }
        .onAppear {
            checkServer() // Initial server check
            /// refresh voices in the background
            cancellable = timer.sink { _ in
                speechSynthesiser.fetchVoices()
            }
        }
        .onDisappear {
            cancellable?.cancel()
        }
    }
}

#Preview {
    Settings()
}
