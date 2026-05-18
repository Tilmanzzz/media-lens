# Load Strategy (Full vs Delta)

This document describes how full and delta loads should work using only columns that exist in `storage/db/init_v2.sql`.

## Terminology

- **Full load**: Process all rows in a stage.
- **Delta load**: Process only rows that changed since the last successful batch.
- **last_watermark**: A runtime parameter derived from `pipeline_batches.fin_ts`.

## How to Get the Watermark

Use the last successful batch end time per stage.

```sql
SELECT COALESCE(MAX(fin_ts), TIMESTAMPTZ '1970-01-01') AS last_watermark
FROM pipeline_batches
WHERE stage = 'ingestion' AND status = 'done';
```

Repeat per stage by changing `stage` to `silver` or `silver_enriched`.

## Ingestion Stage

Tables: `podcasts`, `episodes`

### Full load

```sql
SELECT * FROM podcasts;
SELECT * FROM episodes;
```

### Delta load

Use `updated_at` (source time). If it is NULL, fall back to `system_updated_at`.

```sql
SELECT *
FROM podcasts
WHERE updated_at > :last_watermark
   OR (updated_at IS NULL AND system_updated_at > :last_watermark);
```

```sql
SELECT *
FROM episodes
WHERE updated_at > :last_watermark
   OR (updated_at IS NULL AND system_updated_at > :last_watermark);
```

## Silver Stage (Segmentation)

Tables: `segments`, `transcript_lines`

### Full load

```sql
SELECT * FROM segments;
SELECT * FROM transcript_lines;
```

### Delta load

Use `system_updated_at` because these rows are produced by your processing.

```sql
SELECT *
FROM segments
WHERE system_updated_at > :last_watermark;
```

```sql
SELECT *
FROM transcript_lines
WHERE system_updated_at > :last_watermark;
```

## Silver Enriched Stage

Tables: `fact_checked_claims`, `segment_embeddings`

### Full load

```sql
SELECT * FROM fact_checked_claims;
SELECT * FROM segment_embeddings;
```

### Delta load

Use `system_updated_at` because these rows are produced by your enrichment.

```sql
SELECT *
FROM fact_checked_claims
WHERE system_updated_at > :last_watermark;
```

```sql
SELECT *
FROM segment_embeddings
WHERE system_updated_at > :last_watermark;
```

## Notes

- `pipeline_batches` should be written by the runner for each stage.
- For delta loads, update `pipeline_batches.fin_ts` at the end of a successful run.
- If a stage needs reprocessing, run a full load or reset the watermark strategy.

## Write Patterns (Replace or Append)

Use UPSERT with the unique keys below to **replace existing rows** and **append new rows**.

**Keys**

- `podcasts`: `guid`
- `episodes`: `(podcast_id, guid)`
- `segments`: `(episode_id, segment_idx)`
- `transcript_lines`: `(segment_id, line_idx)`
- `fact_checked_claims`: `(segment_id, claim_idx)`
- `segment_embeddings`: `(segment_id)`

### Example UPSERT (segments)

```sql
INSERT INTO segments (episode_id, segment_idx, title, summary, start_time, end_time, batch_id)
VALUES (:episode_id, :segment_idx, :title, :summary, :start_time, :end_time, :batch_id)
ON CONFLICT (episode_id, segment_idx)
DO UPDATE SET
   title = EXCLUDED.title,
   summary = EXCLUDED.summary,
   start_time = EXCLUDED.start_time,
   end_time = EXCLUDED.end_time,
   system_updated_at = NOW(),
   batch_id = EXCLUDED.batch_id;
```

### Example UPSERT (fact_checked_claims)

```sql
INSERT INTO fact_checked_claims (segment_id, claim_idx, claim, verdict, explanation, sources, batch_id)
VALUES (:segment_id, :claim_idx, :claim, :verdict, :explanation, :sources, :batch_id)
ON CONFLICT (segment_id, claim_idx)
DO UPDATE SET
   claim = EXCLUDED.claim,
   verdict = EXCLUDED.verdict,
   explanation = EXCLUDED.explanation,
   sources = EXCLUDED.sources,
   system_updated_at = NOW(),
   batch_id = EXCLUDED.batch_id;
```

## Action Checklist

1. Read `last_watermark` for the stage from `pipeline_batches`.
2. Run the **delta query** (or full scan).
3. Write results using UPSERT with the keys above.
4. Mark `pipeline_batches.status='done'` and set `fin_ts`.
