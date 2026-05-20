# Silver Enriched Load Strategy (Concept)

## Ziel

Definiert, wie der Silver Enriched Ingest Full-Load und Delta-Load ausfuehrt.
Fokus: Filterung ueber einen effektiven Update-Zeitstempel.

## Begriffe

- **Full-Load**: Alle Datensaetze aus den Silver Enriched Outputs werden geschrieben.
- **Delta-Load**: Nur Datensaetze mit effective_update_ts > watermark werden geschrieben.
- **watermark**: Letzter erfolgreicher Batch-Zeitpunkt (z.B. pipeline_batches.fin_ts).

## Effektiver Zeitstempel

Für jeden Datensatz gilt:

```
effective_update_ts = update_ts
if update_ts is missing or null:
    effective_update_ts = source_update_ts
```

Falls **beide** fehlen, wird der Datensatz im Delta-Load **mitgenommen**,
so dass keine Aenderungen verloren gehen.

## Full-Load

- Alle Eintraege aus Fact Checker, Text Summarizer und Transcript Embedder schreiben.
- Schreibstrategie: UPSERT (oder UPDATE, wo nur Summary-Updates erfolgen).

## Delta-Load

1. watermark ermitteln
2. Nur Datensaetze mit effective_update_ts > watermark schreiben
3. Fehlende effective_update_ts: trotzdem schreiben (konservativ)

## Zieltabellen (init_v2.sql)

- **fact_checked_claims**: Claims je Kapitel (chapter)
- **embeddings**: Kapitel-, Episode-, Podcast-Level Embeddings
- **episodes.summary**: Episode-Zusammenfassungen
- **chapters.summary**: Kapitel-Zusammenfassungen

## Mapping der Silver Enriched Outputs

- Fact Checker Output:
  - claims -> fact_checked_claims
  - chapter_id wird aus record.chapter_id oder record.segment_id genommen
- Summaries Output:
  - episodes -> episodes.summary
  - segments -> chapters.summary
- Embeddings Output:
  - segment_level -> level = 'chapter', chapter_id = segment_id
  - episode_level -> level = 'episode', episode_id = episode_id
  - podcast_level -> level = 'podcast', podcast_id = podcast_id
  - chunk_level wird ignoriert (keine passende Tabelle in init_v2)

## Batch-Bezug

- watermark sollte aus pipeline_batches je Stage gelesen werden.
- Stage fuer Silver Enriched in init_v2 ist aktuell **processing**.
- Bei fehlender Batch-Historie: watermark = 1970-01-01.

## Orchestrierung (PostgreSQL Scheduler)

- Der Ingest wird vom Datenbank-Orchestrator gestartet (z.B. taeglich 12:00).
- Beim Start prueft das Skript den **Gap** zwischen watermark und aktuellem Laufzeitpunkt.
- Falls ein Gap vorhanden ist, wird ein **Delta-Load** ueber den fehlenden Zeitraum gefahren.
- Optional: Bei grossem Gap (z.B. mehrere Tage) kann ein Full-Load erzwungen werden.

## Pseudocode (Delta)

```
watermark = get_watermark(stage)
for record in input:
    ts = record.update_ts or record.source_update_ts
    if ts is None:
        include(record)
    else if ts > watermark:
        include(record)
```

## CLI Beispiel (Full-Load)

```bash
python src/02_processing/silver_enriched/data_processing_full.py --full \
  --fact-checker src/02_processing/silver_enriched/fact_checker/output_factchecker.json \
  --summaries src/02_processing/silver_enriched/text_summarizer/test/output_text_summarizer.json \
  --embeddings src/02_processing/silver_enriched/transcript_embedder/test/embedded_output.json \
  --postgres-url "postgresql://user:pass@localhost:5432/audio_lens"
```
