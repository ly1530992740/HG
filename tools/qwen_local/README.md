# Local Qwen3-0.6B Server

This directory runs the GGUF model stored at:

```text
addons/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q8_0.gguf
```

The bundled runtime is the official `llama.cpp b10144` Windows Vulkan build.
It exposes an OpenAI-compatible API on localhost and does not require an
internet connection after installation.

## Start

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\qwen_local\start_server.ps1
```

Default endpoints:

```text
Health: http://127.0.0.1:8081/health
Chat:   http://127.0.0.1:8081/v1/chat/completions
```

## Test

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\qwen_local\test_chat.ps1
```

For an interactive command-line conversation:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\qwen_local\test_chat.ps1 -Interactive
```

Type `/exit` to close the chat. Interactive questions use `/no_think` by
default for low latency; include `/think` in a question to request deeper
reasoning.

## Stop

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\qwen_local\stop_server.ps1
```

The server defaults to a 4096-token context and non-thinking mode so tactical
responses stay short and fast. Pass `-ContextSize` or `-Port` to the start
script when a different setting is required.
