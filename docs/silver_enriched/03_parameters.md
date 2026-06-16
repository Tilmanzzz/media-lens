# Steuerungs-Parameter

Es gibt zwei Arten von Parametern:

1. **CLI-/Runner-Parameter**: steuern wie ein Lauf ausgeführt wird (Modus, Steps, Testfilter, Logging).
2. **Modul-Configs (JSON)**: steuern was ein Modul fachlich tut (Modell, Provider, Schwellenwerte).

Beide lassen sich kombinieren: CLI-Argumente können auch aus einer JSON-Datei vorbelegt werden
(`--config`), CLI-Argumente überschreiben dabei wie üblich die Defaults.

## 1) Runner-Parameter (`00_pipeline_processing_runner.py`)

| Parameter | Default | Bedeutung |
|---|---|---|
| `--config` | `processing_pipeline_config.json` | Pfad zu einer JSON-Datei mit Default-Werten für alle unten stehenden Argumente |
| `--mode` | `delta` | `full` oder `delta` (siehe [02_load_strategy.md](02_load_strategy.md)) |
| `--steps` | `text_summarizer,fact_checker,embedder,emotion_scoring` | Komma-Liste der auszuführenden Steps, oder `processing` für alle |
| `--batch-id` | `None` | Optionaler, vorgegebener Batch (siehe Glossar) |
| `--dry-run` | `False` | Wenn gesetzt: keine DB-Schreibvorgänge, kein Batch-Eintrag |
| `--testing` | `False` | Schaltet die Testfilter unten frei |
| `--test-episode-id` | `None` | Test: nur diese eine Episode verarbeiten |
| `--test-chapter-limit` | `3` | Test: max. Anzahl Kapitel dieser Episode |
| `--test-end-watermark` | `None` | Test: ISO-Zeitstempel als Obergrenze für `preprocessing_updated_at` |
| `--log-enabled` | `False` | Logging an/aus |
| `--log-level` | `INFO` | Log-Level (`DEBUG`, `INFO`, `WARNING`, `ERROR`, ...) |
| `--log-dir` | `../logs` | Zielordner für die Log-Datei |
| `--log-file` | `processing_pipeline.log` | Dateiname des Logs |

Jeder einzelne Step (`01_..._text_summarizer.py` usw.) akzeptiert dieselben Parameter
(mit eigenem `--stage`-Default und eigenem `--log-file`-Default) und kann komplett unabhängig
vom Runner aufgerufen werden.

### Beispiel-Konfigurationsdatei (`processing_pipeline_config.json`)

```json
{
  "mode": "delta",
  "batch_id": null,
  "dry_run": false,
  "steps": "text_summarizer,fact_checker,embedder,emotion_scoring",
  "testing": false,
  "test_episode_id": null,
  "test_chapter_limit": null,
  "test_end_watermark": "2026-05-17T12:00:00+00:00",
  "log_enabled": true,
  "log_level": "INFO",
  "log_dir": "../logs",
  "log_file": "processing_pipeline.log"
}
```

## 2) Modul-Configs (fachliche Steuerung)

### `text_summarizer/text_summarizer_config.json`

| Parameter | Beispielwert | Bedeutung |
|---|---|---|
| `provider` | `gemini` | LLM-Anbieter: `gemini` oder `ollama` (lokal) |
| `model` | `gemini-2.5-flash` | Konkretes Modell |
| `temperature` | `0.0` | Kreativität des LLM (0 = deterministisch) |
| `llm_options` | `{}` | Zusätzliche, providerspezifische Optionen |
| `logging_enabled`, `log_level`, `log_dir`, `log_file` | - | Logging (siehe [05_logging.md](05_logging.md)) |

### `fact_checker/fact_checker_config.json`

| Parameter | Beispielwert | Bedeutung |
|---|---|---|
| `provider` / `model` / `temperature` | `gemini` / `gemini-2.5-flash` / `0.0` | Wie oben |
| `region` | `us-en` | Region für die Web-Suche (DDGS) |
| `max_queries_per_claim` | `1` | Wie viele Suchanfragen je Behauptung generiert werden |
| `max_search_results_per_query` | `3` | Wie viele Suchergebnisse je Anfrage berücksichtigt werden |
| `max_sources_per_claim` | `3` | Wie viele Quellen maximal je Behauptung gespeichert werden |
| `allowed_verdicts` | `["TRUE","MOSTLY_TRUE","MISLEADING","FALSE","UNVERIFIABLE"]` | Erlaubte Bewertungs-Labels |
| `logging_enabled`, `log_level`, `log_dir`, `log_file` | - | Logging |

### `transcript_embedder/transcript_embedder_config.json`

| Parameter | Beispielwert | Bedeutung |
|---|---|---|
| `model` | `qwen3-embedding:4b` | Embedding-Modell (über Ollama) |
| `task_instruction` | "Represent this podcast transcript segment..." | Prompt-Präfix, das dem Modell den Anwendungsfall mitgibt |
| `input_text_field` | `transcription` | Welches Feld im Input-Objekt den Text enthält (Fallbacks: `transcript_text`, `transcription`) |
| `batch_size` | `32` | Wie viele Texte pro Embedding-Aufruf gebündelt werden |
| `max_podcast_sample_size` | `5` | Begrenzung für Podcast-Level-Sampling (Performance) |
| `embed_options` | `{}` | Zusätzliche Optionen für den Embedding-Call |
| `logging_enabled`, `log_level`, `log_dir`, `log_file` | - | Logging |

### `emotion_analyser/emotion_analyser_config.json`

| Parameter | Beispielwert | Bedeutung |
|---|---|---|
| `model_id` | `superb/wav2vec2-base-superb-er` | Hugging-Face-Modell für Emotionserkennung |
| `cache_dir` | `./hf_superb` | Lokaler Cache für Modellgewichte |
| `sample_rate` | `16000` | Erwartete Abtastrate für das Modell |
| `audio_dir` | `./audio_test` | Ordner für lokale Test-Audiodateien |
| `ffmpeg_binary` | `ffmpeg` | Pfad/Name der ffmpeg-Binärdatei |
| `ffmpeg_audio_channels` | `1` | Mono-Konvertierung beim Audio-Zuschnitt |
| `ffmpeg_audio_rate` | `16000` | Ziel-Abtastrate beim Audio-Zuschnitt |
| `minio_bucket` | `bronze` | MinIO-Bucket, aus dem die Original-Audiodateien geladen werden |
| `audio_cache_dir` | `~/.audio_lens_cache/emotion_scoring` | Persistenter lokaler Cache für ganze Episoden-Audiodateien (vermeidet Mehrfach-Downloads) |
| `clear_cache_before_run` | `true` | Ob der Cache vor jedem Lauf geleert wird |
| `logging_enabled`, `log_level`, `log_dir`, `log_file` | - | Logging |

Zusätzlich kann `--cache-dir` (CLI) oder die Umgebungsvariable `EMOTION_CACHE_DIR` den
`audio_cache_dir`-Wert überschreiben. Priorität: CLI > Env-Var > Config-Datei.

## Priorität bei Überschneidungen

```mermaid
flowchart LR
    A[Hartcodierter Default im argparse] --> B[Wert aus --config JSON-Datei]
    B --> C[Explizit angegebenes CLI-Argument]
    C --> D[Tatsächlich verwendeter Wert]
```

Je weiter rechts, desto höher die Priorität. Ein explizit auf der Kommandozeile übergebenes
Argument gewinnt immer.
