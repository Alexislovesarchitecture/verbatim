# Feature Parity Matrix

| Area | Final Product Status | Source of Truth |
| --- | --- | --- |
| Provider selection and capability gating | Retained | macOS shell + Rust core |
| Provider-specific language persistence | Retained | macOS shell + Rust core |
| Local model download/install state | Retained | macOS shell |
| Overlay, menu bar, and dictation controls | Retained | macOS shell |
| History and dictionary | Retained | macOS shell |
| Style settings and conservative formatting | Retained | Rust core + macOS shell |
| Apple Speech local provider | Retained | macOS shell |
| Whisper local runtime | Retained | macOS shell |
| Parakeet local runtime with explicit platform gating | Retained | macOS shell + Rust core |
| Windows native shell | Added scaffold | final product layout |
| Linux native shell | Added scaffold | final product layout |
| Remote OpenAI transcription | Retired | legacy only |
| Remote/OpenAI refine logic | Retired | legacy only |
| Ollama local logic routing | Retired | legacy only |
| Legacy WhisperKit / legacy whisper.cpp routing | Retired | legacy only |
