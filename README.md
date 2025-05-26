[<img src="https://img.shields.io/badge/App_Store-0D96F6?&logo=app-store&logoColor=white">](https://apps.apple.com/gb/app/enchanted-llm/id6474268307)
![Swift](https://img.shields.io/badge/swift-F54A2A?&logo=swift&logoColor=white)
![Release](https://img.shields.io/github/v/release/augustdev/enchanted)
![Stars](https://img.shields.io/github/stars/augustdev/enchanted.svg)
[<img src="https://img.shields.io/twitter/url?url=https%3A%2F%2Ftwitter.com%2Famgauge">](https://twitter.com/amgauge)
![iOS](https://img.shields.io/badge/iOS-000000?&logo=os&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-000000?style=?&logo=os&logoColor=white)
![visionOS](https://img.shields.io/badge/visionOS-000000?style=?&logo=os&logoColor=white)

# Enchanted

Enchanted is open source, elegant macOS/iOS/visionOS app for working with privately hosted models. It supports [Ollama](https://github.com/jmorganca/ollama) (e.g., Llama 2, Mistral, Vicuna, Starling) and other OpenAI API-compatible servers like Llama.cpp and MLX. It's essentially a ChatGPT-like UI that connects to your private models. The goal of Enchanted is to deliver a product allowing unfiltered, secure, private, and multimodal experiences across all of your devices in the iOS ecosystem (macOS, iOS, Watch, Vision Pro).

If you like the project, consider leaving a ⭐️ and following on [𝕏](https://twitter.com/amgauge).

## App Store

[<img src="https://i.ibb.co/7WXt3qZ/download.png">](https://apps.apple.com/gb/app/enchanted-llm/id6474268307)

Note: You will need to run your own LLM server to use the app. Read instructions below.

## Demo

[<img src="./assets/promo.png">](https://www.youtube.com/watch?v=zW3roZ_vM5Q)

[Vision Pro Demo](https://www.youtube.com/watch?v=y4ZeGU5IdHA)

## Showcase

### Macbook

![image](https://github.com/AugustDev/enchanted/assets/5672094/32a6a203-19a2-4cc1-adc9-cfac8445dd42)

#### Dark mode

![image](https://github.com/AugustDev/enchanted/assets/5672094/6202d235-6c34-4f79-b08a-a372fca0439e)

#### Settings

<img src="https://github.com/AugustDev/enchanted/assets/5672094/b03acfc7-cbc3-4bab-92cd-73d3eb75b47e" width="1000" height="100%">

#### Completions

 <img src="https://github.com/AugustDev/enchanted/assets/5672094/5ca80a65-1bec-4d6c-8065-f0a26861c3c2" width="1000" height="100%">

#### Use from anywhere

https://github.com/AugustDev/enchanted/assets/5672094/221d2a48-9218-4579-b284-a1ad2845e4d6

#### Build custom prompt templates and use anywhere

<img width="599" alt="Xnapper-2024-05-02-18 57 19" src="https://github.com/AugustDev/enchanted/assets/5672094/7b69fe50-5399-4c0b-a269-f28353b8ca27">

https://github.com/AugustDev/enchanted/assets/5672094/8bdebd5e-2910-4855-bb10-91239cafbc28

#### Custom completion

https://github.com/AugustDev/enchanted/assets/5672094/2ef476e7-8fc5-4992-9152-6df3847056d6

### iPhone

Multimodal

<img src="https://github.com/AugustDev/enchanted/assets/5672094/f2a7dafa-9470-4689-9f5a-27b6eb0e168d" width="1000" height="100%">

Markdown

<img src="https://github.com/AugustDev/enchanted/assets/5672094/9caefcb2-69eb-46d0-8d4f-b6269d7c2937" width="1000" height="100%">

Conversation history

<img width="959" alt="Xnapper-2024-05-03-12 00 28" src="https://github.com/AugustDev/enchanted/assets/5672094/7dade8ec-e94d-4936-9237-f2f2bc1533f2">

### Vision Pro

<img width="1534" alt="image" src="https://github.com/AugustDev/enchanted/assets/5672094/810f600a-4377-48e3-9c94-7bb90b78acaf">

<img width="1496" alt="image" src="https://github.com/AugustDev/enchanted/assets/5672094/6014a0b4-03ed-4def-b26c-b9baefad3781">

## Features

- Connect to Ollama, Llama.cpp, MLX, or any OpenAI API-compatible server.
- Text to Speech (Read Aloud)
- Conversation history included in the API calls
- Dark/Light mode
- Conversation history is stored on your device
- Markdown support (nicely displays tables/lists/code blocks)
- Voice prompts
- Image attachments for prompts
- Specify system prompt used for every conversations
- Edit message content or submit message with different model
- Delete single conversation / delete all conversations
- macOS Spotlight panel <kbd>Ctrl</kbd>+<kbd>⌘</kbd>+<kbd>K</kbd>
- All features works offline (if your LLM server is local)

## Usage instructions

### Connecting to Ollama

Enchanted requires Ollama v0.1.14 or later.

#### Case 1. You run Ollama server with public access

1. Download Enchanted app from the App Store.
2. In App Settings:
    - Select "Ollama" as the LLM Provider.
    - Specify your server endpoint in the "Ollama server URI" field.
    - If your Ollama server requires a bearer token, enter it in the "Bearer Token" field.

You're done! Make a prompt.

#### Case 2. You run Ollama on your computer (local access)

[Video instructions here](https://www.youtube.com/watch?v=SFeVCiLOABM)

1. Start Ollama server (e.g., `ollama serve`) and download models for usage (e.g., `ollama pull llama3`).
2. **Option A (Recommended for local use):** Ensure your Ollama server is accessible from your local network. Typically, Ollama listens on `http://localhost:11434` by default. You can use this URI directly in Enchanted if the app is running on the same machine. If running on a different device on the same network, use your computer's local IP address (e.g., `http://192.168.1.100:11434`).
3. **Option B (Public access via ngrok - use with caution):** Install ngrok to forward your Ollama server to make it publicly accessible.
   ```shell
   ngrok http 11434 --host-header="localhost:11434"
   ```
   Copy the "Forwarding" URL that ngrok provides (e.g., `https://b377-82-132-216-51.ngrok-free.app`). Your Ollama server API is now accessible through this temporary public URL.
4. Download Enchanted app from the App Store.
5. In App Settings:
    - Select "Ollama" as the LLM Provider.
    - Specify your server endpoint (from step 2A or 2B) in the "Ollama server URI" field.
    - If your Ollama server requires a bearer token (not typical for default local setups), enter it.

You're done! Make a prompt.

### Connecting to Other LLM Providers (Llama.cpp, MLX)

Enchanted can also connect to other LLM servers that are compatible with the OpenAI API, such as Llama.cpp and MLX.

1.  **Start your LLM Server:**
    *   **Llama.cpp:** Ensure your Llama.cpp server is running and configured for OpenAI API compatibility. This is typically done by running `python -m llama_cpp.server --model /path/to/your/model.gguf`. The default server address is usually `http://localhost:8080`.
    *   **MLX:** Ensure your MLX LM server is running. This is typically done using `python -m mlx_lm.server --model /path/to/your/mlx_model_directory`. The default server address is usually `http://localhost:8088`.
2.  **Configure in Enchanted:**
    *   Open Enchanted and go to **Settings**.
    *   In the "LLM Provider" section, select your desired provider (Llama.cpp or MLX) from the picker.
    *   In the corresponding section for your chosen provider:
        *   Enter the server URI (e.g., `http://localhost:8080` for Llama.cpp, `http://localhost:8088` for MLX).
        *   If your server requires an API key (not common for local Llama.cpp/MLX setups but supported), enter it in the "API Key (Optional)" field.
    *   Tap "Check Server Connection" to ensure the app can reach your server and load models.
    *   Choose a default model from the populated list.
    *   Tap "Save".

You're done! You should now be able to chat with models hosted by your Llama.cpp or MLX server.

# Contact

For any questions please do not hesitate to contact me at augustinas@subj.org

# Author

Augustinas Malinauskas
