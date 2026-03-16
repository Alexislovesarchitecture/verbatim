# Retired Legacy Features

The final Verbatim product is local-first and cross-shell. The following legacy MVP features are intentionally not carried forward:

- remote OpenAI transcription paths
- remote OpenAI refine/LLM formatting paths
- Ollama logic-routing paths
- legacy WhisperKit and legacy whisper.cpp runtime branches
- setup flows dedicated to cloud API keys and remote model catalogs

Their behavior is replaced by:

- local provider selection
- Rust-owned deterministic formatting and policy
- native shell diagnostics and capability gating
- platform-native local runtime management
