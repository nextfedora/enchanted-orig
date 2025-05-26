//
//  SettingsView.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    
    @Binding var selectedProvider: ModelProvider
    @Binding var ollamaUri: String
    @Binding var ollamaBearerToken: String
    @Binding var llamaCppUri: String
    @Binding var llamaCppApiKey: String
    @Binding var mlxUri: String
    @Binding var mlxApiKey: String
    
    @Binding var systemPrompt: String
    @Binding var vibrations: Bool
    @Binding var colorScheme: AppColorScheme
    @Binding var defaultModelName: String
    @Binding var appUserInitials: String
    @Binding var pingInterval: String // This might become provider-specific
    @Binding var voiceIdentifier: String
    
    @Binding var currentServerStatus: Bool? // Changed from ollamaStatus
    
    var save: () -> ()
    var checkServer: () -> ()
    var deleteAll: () -> ()
    var currentProviderLanguageModels: [LanguageModelSD] // Changed from ollamaLanguageModels
    var voices: [AVSpeechSynthesisVoice]
    
    @State private var deleteConversationsDialog = false
    
    var body: some View {
        VStack {
            ZStack {
                HStack {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(.label))
                    }
                    
                    Spacer()
                    
                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(.label))
                    }
                }
                
                HStack {
                    Spacer()
                    Text("Settings")
                        .font(.system(size: 16))
                        .fontWeight(.medium)
                        .foregroundStyle(Color(.label))
                    Spacer()
                }
            }
            .padding()
            
            Form {
                Section(header: Text("LLM Provider").font(.headline)) {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(ModelProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue.capitalized).tag(provider)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle()) // Or .menu for more options
                    .onChange(of: selectedProvider) { _, _ in
                         currentServerStatus = nil // Reset status on provider change
                         checkServer()
                    }
                    
                    Button(action: checkServer) {
                        HStack {
                            Text("Check Server Connection")
                            Spacer()
                            if currentServerStatus != nil {
                                Image(systemName: currentServerStatus == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(currentServerStatus == true ? .green : .red)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                }
                
                if selectedProvider == .ollama {
                    Section(header: Text("Ollama Server").font(.headline)) {
                        TextField("Ollama server URI", text: $ollamaUri, onCommit: checkServer)
                            .textContentType(.URL)
                            .disableAutocorrection(true)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if !os(macOS)
                            .padding(.top, 8)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
#endif
                        TextField("Bearer Token (Optional)", text: $ollamaBearerToken)
                            .disableAutocorrection(true)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .autocapitalization(.none)
#endif
                    }
                }
                
                if selectedProvider == .llamaCpp {
                    Section(header: Text("Llama.cpp Server").font(.headline)) {
                        TextField("Llama.cpp server URI", text: $llamaCppUri, onCommit: checkServer)
                            .textContentType(.URL)
                            .disableAutocorrection(true)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if !os(macOS)
                            .padding(.top, 8)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
#endif
                        TextField("API Key (Optional)", text: $llamaCppApiKey)
                            .disableAutocorrection(true)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .autocapitalization(.none)
#endif
                    }
                }
                
                if selectedProvider == .mlx {
                    Section(header: Text("MLX Server").font(.headline)) {
                        TextField("MLX server URI", text: $mlxUri, onCommit: checkServer)
                            .textContentType(.URL)
                            .disableAutocorrection(true)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if !os(macOS)
                            .padding(.top, 8)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
#endif
                        TextField("API Key (Optional)", text: $mlxApiKey)
                            .disableAutocorrection(true)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .autocapitalization(.none)
#endif
                    }
                }
                
                Section(header: Text("Model Settings").font(.headline)) {
                    VStack(alignment: .leading) {
                        Text("System Prompt")
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 13))
                            .cornerRadius(4)
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: 100)
                    }
                    
                    Picker(selection: $defaultModelName) {
                        ForEach(currentProviderLanguageModels, id:\.self) { model in
                            Text(model.name).tag(model.name)
                        }
                    } label: {
                        Label {
                            Text("Default Model")
                        } icon: {
                            // Generic icon or provider specific
                            Image(selectedProvider.rawValue) // Assuming you have images named "ollama.png", "llamaCpp.png", "mlx.png"
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(Color(.label))
                                .frame(width: 24, height: 24)
                        }
                    }
                    
                    TextField("Ping Interval (seconds)", text: $pingInterval) // This might need to be provider-specific in future
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Section(header: Text("App Settings").font(.headline).padding(.top, 20)) {
#if os(iOS)
                    Toggle(isOn: $vibrations, label: {
                        Label("Vibrations", systemImage: "water.waves")
                            .foregroundStyle(Color.label)
                    })
#endif
                    Picker(selection: $colorScheme) {
                        ForEach(AppColorScheme.allCases, id:\.self) { scheme in
                            Text(scheme.toString).tag(scheme.id)
                        }
                    } label: {
                        Label("Appearance", systemImage: "sun.max")
                            .foregroundStyle(Color.label)
                    }
                    
                    Picker(selection: $voiceIdentifier) {
                        ForEach(voices, id:\.self.identifier) { voice in
                            Text(voice.prettyName).tag(voice.identifier)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Label("Voice", systemImage: "waveform")
                                .foregroundStyle(Color.label)
                            Text("Download more voices in system settings.")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        
                        Button(action: {
#if os(macOS)
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpeakableItems") {
                                NSWorkspace.shared.open(url)
                            }
#else
                            let url = URL(string: "App-Prefs:root=ACCESSIBILITY&path=SPEECH_CONTENT_AND_SETTINGS") // Updated path for modern iOS
                            if let url = url, UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            } else {
                                // Fallback for older iOS or if specific path fails
                                let generalUrl = URL(string: "App-Prefs:root=ACCESSIBILITY")
                                if let generalUrl = generalUrl, UIApplication.shared.canOpenURL(generalUrl) {
                                    UIApplication.shared.open(generalUrl, options: [:], completionHandler: nil)
                                }
                            }
#endif
                        }) {
                            Text("Open System Settings")
                                .font(.caption)
                        }
                        .buttonStyle(BorderlessButtonStyle()) // Use BorderlessButtonStyle for a cleaner look in a list
                        .padding(.top, 4) // Add some spacing
                    }
                    
                    TextField("Initials", text: $appUserInitials)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                        .autocapitalization(.none)
#endif
                    
                    Button(action: {deleteConversationsDialog.toggle()}) {
                        HStack {
                            Spacer()
                            Text("Clear All Data")
                                .foregroundStyle(Color(.systemRed))
                                .padding(.vertical, 6)
                            Spacer()
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .preferredColorScheme(colorScheme.toiOSFormat)
        .confirmationDialog("Delete All Data?", isPresented: $deleteConversationsDialog) {
            Button("Delete", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all conversations and model data.")
        }
    }
}

#Preview {
    SettingsView(
        selectedProvider: .constant(.ollama),
        ollamaUri: .constant("http://localhost:11434"),
        ollamaBearerToken: .constant(""),
        llamaCppUri: .constant("http://localhost:8080"),
        llamaCppApiKey: .constant(""),
        mlxUri: .constant("http://localhost:8088"),
        mlxApiKey: .constant(""),
        systemPrompt: .constant("You are an intelligent assistant solving complex problems."),
        vibrations: .constant(true),
        colorScheme: .constant(.light),
        defaultModelName: .constant("llama3"),
        appUserInitials: .constant("AM"),
        pingInterval: .constant("5"),
        voiceIdentifier: .constant("sample"),
        currentServerStatus: .constant(true),
        save: {},
        checkServer: {},
        deleteAll: {},
        currentProviderLanguageModels: LanguageModelSD.sample,
        voices: []
    )
}
