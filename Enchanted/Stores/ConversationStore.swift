//
//  ChatsStore.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData
// import OllamaKit // OKChatRequestData and OKChatResponse are no longer directly used here
import Combine
import SwiftUI

@Observable
final class ConversationStore: Sendable {
    static let shared = ConversationStore(swiftDataService: SwiftDataService.shared)
    
    private var swiftDataService: SwiftDataService
    private var generationTask: Task<Void, Never>? // Changed from AnyCancellable for the new Task-based approach
    
    /// For some reason (SwiftUI bug / too frequent UI updates) updating UI for each stream message sometimes freezes the UI.
    /// Throttling UI updates seem to fix the issue.
    private var currentMessageBuffer: String = ""
#if os(macOS)
    private let throttler = Throttler(delay: 0.1)
#else
    private let throttler = Throttler(delay: 0.1)
#endif
    
    @MainActor var conversationState: ConversationState = .completed
    @MainActor var conversations: [ConversationSD] = []
    @MainActor var selectedConversation: ConversationSD?
    @MainActor var messages: [MessageSD] = []
    
    init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
    }
    
    func loadConversations() async throws {
        print("loading conversations")
        let fetchedConversations = try await swiftDataService.fetchConversations()
        DispatchQueue.main.async {
            self.conversations = fetchedConversations
        }
        print("loaded conversations")
    }
    
    func deleteAllConversations() {
        Task {
            DispatchQueue.main.async { [weak self] in
                self?.messages = []
                self?.selectedConversation = nil
            }
            try? await swiftDataService.deleteConversations()
            try? await swiftDataService.deleteMessages()
            try? await loadConversations()
        }
    }
    
    func deleteDailyConversations(_ date: Date) {
        Task {
            DispatchQueue.main.async { [self] in
                selectedConversation = nil
                messages = []
            }
            try? await swiftDataService.deleteConversations() // This seems to delete ALL conversations, might need refinement
            try? await loadConversations()
        }
    }
    
    
    func create(_ conversation: ConversationSD) async throws {
        try await swiftDataService.createConversation(conversation)
    }
    
    func reloadConversation(_ conversation: ConversationSD) async throws {
        let (messages, selectedConversation) = try await (
            swiftDataService.fetchMessages(conversation.id),
            swiftDataService.getConversation(conversation.id)
        )
        
        DispatchQueue.main.async {
                self.messages = messages.sorted { $0.createdAt < $1.createdAt } // Ensure messages are sorted
                self.selectedConversation = selectedConversation
        }
    }
    
    func selectConversation(_ conversation: ConversationSD) async throws {
        try await reloadConversation(conversation)
    }
    
    func delete(_ conversation: ConversationSD) async throws {
        try await swiftDataService.deleteConversation(conversation)
        let fetchedConversations = try await swiftDataService.fetchConversations()
        DispatchQueue.main.async {
            self.selectedConversation = nil
            self.conversations = fetchedConversations
        }
    }
    
    @MainActor func stopGenerate() {
        generationTask?.cancel() // Cancel the Task
        handleComplete() // Ensure state is updated
        withAnimation {
            conversationState = .completed
        }
    }
    
    @MainActor
    func sendPrompt(userPrompt: String, model: LanguageModelSD, image: Image? = nil, systemPrompt: String = "", trimmingMessageId: String? = nil) {
        guard userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else { return }
        
        let conversation = selectedConversation ?? ConversationSD(name: userPrompt)
        conversation.updatedAt = Date.now
        conversation.model = model // model is LanguageModelSD
        
        // Get the correct service
        guard let provider = model.modelProvider else {
            self.handleError("Model provider information is missing.")
            return
        }

        guard let currentService = LanguageModelStore.shared.getService(for: provider) else {
            self.handleError("Could not find a configured service for provider \(provider.rawValue).")
            return
        }
        
        print("model", model.name)
        print("provider", provider.rawValue)
        print("conversation", conversation.name)
        
        /// trim conversation if on edit mode
        if let trimmingMessageId = trimmingMessageId {
            let sortedMessages = conversation.messages.sorted { $0.createdAt < $1.createdAt }
            if let trimIndex = sortedMessages.firstIndex(where: { $0.id.uuidString == trimmingMessageId }) {
                conversation.messages = Array(sortedMessages.prefix(upTo: trimIndex))
            }
        }
        
        /// add system prompt to very first message in the conversation
        if !systemPrompt.isEmpty && conversation.messages.filter({$0.role == "system"}).isEmpty {
            let systemMessage = MessageSD(content: systemPrompt, role: "system")
            systemMessage.conversation = conversation
            // conversation.messages.insert(systemMessage, at: 0) // This line was missing for actually adding it
        }
        
        /// construct new message
        let userMessage = MessageSD(content: userPrompt, role: "user", image: image?.render()?.compressImageData())
        userMessage.conversation = conversation
        
        // Add user message to the conversation before preparing history for the service
        // This ensures the current prompt is part of the history sent to the service
        // conversation.messages.append(userMessage) // This was done later, should be done before creating assistant message

        let assistantMessage = MessageSD(content: "", role: "assistant")
        assistantMessage.conversation = conversation
        
        conversationState = .loading
        
        Task {
            // Persist changes before sending
            // Add system message if needed (if it wasn't persisted correctly before)
            if !systemPrompt.isEmpty && !conversation.messages.contains(where: {$0.role == "system"}) {
                 let systemMessageToAdd = MessageSD(content: systemPrompt, role: "system")
                 systemMessageToAdd.conversation = conversation
                 try await swiftDataService.createMessage(systemMessageToAdd) // Persist system message
            }
            try await swiftDataService.createMessage(userMessage) // Persist user message
            try await swiftDataService.createMessage(assistantMessage) // Persist empty assistant message
            try await swiftDataService.updateConversation(conversation) // Save conversation (especially if new)
            
            try await reloadConversation(conversation) // Reload to get all messages in order and update UI
            try? await loadConversations() // Refresh conversation list
            
            if await currentService.reachable() {
                // Use Task.detached or a custom actor for background work
                generationTask = Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self = self else { return }

                    // Prepare message history as [MessageSD]
                    // The historicalMessages should be all messages *before* the new userPrompt
                    // However, the current `sendMessage` protocol takes the latest prompt separately.
                    // Let's pass all messages up to the one before the assistant's empty message.
                    
                    let serviceModel = LanguageModel(name: model.name, provider: provider, imageSupport: model.imageSupport)
                    
                    // Fetch messages from the conversation again to ensure order and inclusion of system/user prompts
                    // This ensures we are sending the most up-to-date history
                    let historicalMessages = conversation.messages
                        .filter { $0.id != assistantMessage.id } // Exclude the empty assistant message
                        .sorted { $0.createdAt < $1.createdAt }

                    do {
                        let stream = try await currentService.sendMessage(
                            prompt: userPrompt, // The latest user prompt
                            model: serviceModel,
                            messages: historicalMessages 
                        )

                        for try await responseContentChunk in stream {
                            if Task.isCancelled { break }
                            await MainActor.run { // Ensure UI updates are on the main thread
                                self.handleReceiveStream(responseContentChunk)
                            }
                        }
                        if Task.isCancelled {
                             await MainActor.run { self.handleError("Cancelled") }
                        } else {
                             await MainActor.run { self.handleComplete() }
                        }
                    } catch {
                        if Task.isCancelled {
                            await MainActor.run { self.handleError("Cancelled") }
                        } else {
                            await MainActor.run {
                                self.handleError(error.localizedDescription)
                            }
                        }
                    }
                }
            } else {
                await MainActor.run { // Ensure UI updates are on the main thread
                     self.handleError("Service for \(provider.rawValue) is unreachable.")
                }
            }
        }
    }
    
    @MainActor
    private func handleReceiveStream(_ contentChunk: String) {
        if messages.isEmpty { return }

        currentMessageBuffer = currentMessageBuffer + contentChunk
        
        throttler.throttle { [weak self] in
            guard let self = self else { return }
            // Ensure we are appending to the last message, which should be the assistant's
            if let lastMessage = self.messages.last, lastMessage.role == "assistant" {
                 // It's important that self.messages is the up-to-date list from the main actor.
                 // Accessing self.messages.last directly might be okay if throttler runs on main,
                 // but direct index access is safer.
                let assistantMessageIndex = self.messages.count - 1
                self.messages[assistantMessageIndex].content.append(self.currentMessageBuffer)
            } else {
                // This case might indicate an issue if there's no assistant message to append to.
                // For now, we'll assume an assistant message was already created and is the last one.
                print("Warning: No assistant message found or last message is not assistant to append stream to.")
            }
            self.currentMessageBuffer = ""
        }
    }
    
    @MainActor
    private func handleError(_ errorMessage: String) {
        guard let lastMessage = messages.last, lastMessage.role == "assistant" else {
            // If there's no last message, or it's not an assistant message, create one for the error.
            // This could happen if the error occurs before the assistant message is set up.
            let errorConversation = selectedConversation ?? ConversationSD(name: "Error Conversation")
            if selectedConversation == nil {
                Task { try? await swiftDataService.createConversation(errorConversation) }
            }
            let errorMsg = MessageSD(content: "Error: \(errorMessage)", role: "assistant", error: true, done: false)
            errorMsg.conversation = errorConversation
            Task { try? await swiftDataService.createMessage(errorMsg) }
            if let currentConv = selectedConversation {
                Task { try? await reloadConversation(currentConv) }
            } else {
                 DispatchQueue.main.async { self.messages.append(errorMsg) }
            }
            withAnimation { conversationState = .error(message: errorMessage) }
            return
        }
        
        lastMessage.error = true
        lastMessage.done = false // Typically, an error means it's not "done" successfully
        
        Task(priority: .background) {
            try? await swiftDataService.updateMessage(lastMessage)
        }
        
        withAnimation {
            conversationState = .error(message: errorMessage)
        }
    }
    
    @MainActor
    private func handleComplete() {
        // If currentMessageBuffer has content, flush it.
        if !currentMessageBuffer.isEmpty {
            if let lastMessage = messages.last, lastMessage.role == "assistant" {
                messages[messages.count - 1].content.append(currentMessageBuffer)
            }
            currentMessageBuffer = ""
        }

        guard let lastMessage = messages.last, lastMessage.role == "assistant" else {
            // This case should ideally not happen if an assistant message was created.
            // If it does, it might mean the stream completed without any assistant message setup.
            print("Warning: No assistant message found to mark as complete.")
            withAnimation { conversationState = .completed }
            return
        }
        
        lastMessage.error = false
        lastMessage.done = true
        
        Task(priority: .background) {
            // Persist the final state of the message
            try? await self.swiftDataService.updateMessage(lastMessage)
        }
        
        withAnimation {
            conversationState = .completed
        }
    }
}
