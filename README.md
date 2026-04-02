# audio-lens

# Branching Strategy mit rebase:

- feature/{name}
- hotfix/{name}
- release
- main

# Architecture

```

                Podcast RSS / APIs
                        │
                        ▼
                 Ingestion Layer
                        │
                        ▼
                 Raw Storage (bronze)
                        │
                        ▼
                 Processing Layer (silver)
              (Transcription + Chunking)
                        │
                        ▼
                Enriching Layer (silver_enriched)
         (Sentiment / Fact Check / Embeddings)
                │                       │
                ▼                       ▼
        Metadata Database          Vector Index
           PostgreSQL                 Qdrant
                │                       │
                └──────────────┬────────┘
                               ▼
                            Backend
                               ▼
                            Frontend
```
