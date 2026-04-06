# Silver Enriched Layer: Architecture and Core Concepts

## Purpose

The silver_enriched stage turns intermediate podcast data into higher-value semantic artifacts:

- Emotion labels from audio
- Claim-level fact-check verdicts with evidence links
- Episode and segment summaries
- Chunk, segment, and episode embeddings for semantic retrieval/vector indexing

This stage blends deterministic processing (grouping, sorting, parsing) with model-driven reasoning (classification, extraction, summarization, verification).

## Scope in Source Tree

Covered modules in this document:

- src/02_processing/silver_enriched/emotion_analyser
- src/02_processing/silver_enriched/fact_checker
- src/02_processing/silver_enriched/text_summarizer
- src/02_processing/silver_enriched/transcript_embedder

Shared utility:

- src/02_processing/common/app_logger.py

## High-Level Architecture

```mermaid
flowchart LR
    A[Input: Audio + Transcript Chunks] --> B[Emotion Analyser]
    A --> C[Fact Checker]
    A --> D[Text Summarizer]
    A --> J[Transcript Embedder]

    B --> E[(Emotion Output JSON)]
    C --> F[(Fact-check Output JSON)]
    D --> G[(Episode/Segment Summaries)]
    J --> K[(Chunk/Episode/Segment Embeddings)]

    H[JSON Config per Module] --> B
    H --> C
    H --> D
    H --> J

    I[Shared AppLogger] --> B
    I --> C
    I --> D
    I --> J
```

## Design Pattern Used Across Modules

All four modules follow the same design approach:

1. Configuration-first setup using a typed dataclass loaded from JSON.
2. A core class that owns the domain logic and external model clients.
3. An executable script for CLI-style local runs and quick validation.
4. Shared logger integration with configurable level, file name, and log directory.

This pattern keeps runtime behavior configurable without code edits and supports both notebooks and script execution.

## Module 1: Emotion Analyser

### What it does

Emotion Analyser classifies speaker emotion from audio clips. It supports wav natively and m4a through ffmpeg conversion.

### Model and tooling

- Hugging Face model: superb/wav2vec2-base-superb-er
- Libraries: transformers, torch, librosa
- Optional conversion dependency: ffmpeg

### Runtime flow

```mermaid
flowchart TD
    A[Load EmotionConfig] --> B[Init AppLogger]
    B --> C[Load Wav2Vec2 model + feature extractor]
    C --> D[Prepare audio path]
    D --> E{Format}
    E -->|wav| F[Load waveform at sample rate]
    E -->|m4a| G[Convert via ffmpeg to wav]
    G --> F
    F --> H[Extract features]
    H --> I[Model inference]
    I --> J[Softmax + argmax]
    J --> K[Map id2label via EmotionLabelCatalog]
    K --> L[Return emotion, id, confidence]
```

Quick term guide:

- Model: The trained neural network that predicts emotion scores from processed audio.
- Feature extractor: The preprocessor that converts raw waveform into model-ready numeric features.
- Model inference: The audio features gets passed to the model which computes output scores (logits) for each emotion class.
- Softmax + argmax: Softmax converts logits to probabilities, and argmax picks the class with the highest probability.

### Key design notes

- Model label mapping is externalized through EmotionLabelCatalog for stable label handling.
- Cache path is configurable so model files can be reused offline.
- Audio pre-processing constraints (sample rate and channel count) are enforced through config.

## Module 2: Fact Checker

### What it does

Fact Checker identifies factual claims in transcripts, gathers web evidence, and returns per-claim verdicts.

### LLM agentic flow concept

This is the most agentic component in silver_enriched. It uses a multi-step orchestration where each step uses a focused prompt and typed post-processing:

1. Extractor LLM-Agent: Claim extraction
2. Researcher LLM-Agent: Query generation per claim
3. Evidence retrieval (DDGS)
4. Judge LLM-Agent: Claim verification with constrained verdict taxonomy

### Model and tooling

- LLM runtime: ChatOllama
- Default model in config: gemma3:4b
- Search tool: ddgs (DuckDuckGo search client)

### Runtime flow

```mermaid
flowchart TD
    A[Transcript] --> B[(LLM) Extractor Agent: Extract factual claims as JSON list]
    B --> C[For each claim]
    C --> D[(LLM) Research Agent: Generate search queries]
    D --> E[DDGS web search]
    E --> F[Compact + dedupe sources]
    F --> G[(LLM) Judge Agent: Verify claim using only provided evidence]
    G --> H[Normalize verdict + sources]
    H --> I[Output JSON: claim, verdict, explanation, sources]
```

### Key design notes

- JSON parsing is hardened with fence stripping and fallback behavior.
- Verdicts are normalized against an allowed list to avoid schema drift.
- If evidence is missing, the system deterministically returns UNVERIFIABLE.

## Module 3: Text Summarizer

### What it does

Text Summarizer produces:

- Episode-level summaries
- Segment-level summaries

It operates over chunked transcripts and preserves logical order before prompting.

### Agentic flow concept

This module uses a lighter orchestration than the fact checker:

- Group chunks by episode or segment
- Sort chunks deterministically
- Build transcript context
- Call prompt-specific chain (episode vs segment)

### Model and tooling

- LLM runtime: ChatOllama
- Default model in config: gemma3:4b
- Prompt composition: langchain_core PromptTemplate

### Runtime flow

```mermaid
flowchart TD
    A[Chunks JSON] --> B{Mode}
    B -->|episode| C[Group by podcast_id + episode_id]
    B -->|segment| D[Group by podcast_id + episode_id + segment_id]
    C --> E[Sort by segment_id/chunk_id]
    D --> F[Sort by chunk_id]
    E --> G[Build full transcript]
    F --> G
    G --> H[Invoke prompt chain]
    H --> I[Return structured summaries]
```

### Key design notes

- The executor supports filtering by podcast_id, episode_id, and segment_id.
- Output can be printed and optionally saved as JSON.
- Prompt intent is explicit and separated by summarization granularity.

## Module 4: Transcript Embedder

### What it does

Transcript Embedder produces dense vector representations from transcript content at three granularities:

- Chunk-level embeddings
- Episode-level embeddings (merged from ordered chunks)
- Segment-level embeddings (merged from ordered chunks)

These vectors can be consumed by downstream vector databases and semantic retrieval workflows.

### Model and tooling

- Embedding runtime: Ollama Python client (`ollama.embed`)
- Default model in config: `qwen3-embedding:4b`
- Optional embedding options via `embed_options` map

### Runtime flow

```mermaid
flowchart TD
    A[Chunks JSON] --> B[Apply optional filters: podcast/episode/segment]
    B --> C{Mode}
    C -->|chunk/all| D[Read input_text_field from each chunk]
    C -->|episode/all| E[Group by podcast_id + episode_id]
    C -->|segment/all| F[Group by podcast_id + episode_id + segment_id]
    E --> G[Sort + concatenate chunk text]
    F --> H[Sort + concatenate chunk text]
    D --> I[Add task instruction prefix]
    G --> I
    H --> I
    I --> J[Batch Ollama embedding calls]
    J --> K[Attach vector + metadata per output record]
```

### Key design notes

- Text field selection is configurable (`input_text_field`) with fallback handling for `transcript_text` and `transcription`.
- Embeddings are generated in configurable batches (`batch_size`) for throughput and memory control.
- Output envelope is normalized under `embedded` with optional `chunk_level`, `episode_level`, and `segment_level` sections depending on run mode.
- Group-level embedding records include `source_chunk_count` for provenance.

## Configuration Model

Each component has a dedicated JSON config file, loaded into a typed dataclass:

- emotion_analyser/emotion_analyser_config.json
- fact_checker/fact_checker_config.json
- text_summarizer/text_summarizer_config.json
- transcript_embedder/transcript_embedder_config.json

Common config behavior:

- Relative path support from working directory and module directory.
- Optional override support in executor scripts.
- Explicit logging controls.

Typical configurable knobs:

- Model selection (model_id or model)
- Inference controls (for example temperature)
- Search limits and verdict policy (fact checker)
- Audio conversion and sample-rate constraints (emotion analyser)
- Logging enabled, level, file, and log directory

## Logging Strategy

All modules use the shared AppLogger builder:

- Toggle logging per module via config
- Write to console and file when enabled
- Use module-specific log files in configurable directories
- Replace handlers on re-init to avoid duplicate log lines in notebook/script reuse

## Operational Notes

- Emotion analysis depends on local audio files and may require ffmpeg for m4a input.
- Fact checking depends on both local LLM availability and outbound web search.
- Summarization depends on local LLM availability and chunk completeness/order.
- Transcript embedding depends on a running Ollama instance and availability of the configured embedding model.

## CLI Entry Points

- src/02_processing/silver_enriched/emotion_analyser/exec_emotion_analyser.py
- src/02_processing/silver_enriched/fact_checker/exec_fact_checker.py
- src/02_processing/silver_enriched/text_summarizer/exec_text_summarizer.py
- src/02_processing/silver_enriched/transcript_embedder/exec_transcript_embedder.py

These scripts are intended for manual execution, quick testing, and integration into larger orchestration later.

## Architectural Takeaway

The silver_enriched layer uses a practical hybrid architecture:

- Deterministic data shaping for reliability and reproducibility.
- Modular model wrappers for replaceable AI capabilities.
- Config-driven behavior to decouple code from environment/runtime choices.
- Agentic LLM orchestration where decomposition is needed (especially fact checking).
- Retrieval-ready vector generation for semantic search and similarity workflows.
