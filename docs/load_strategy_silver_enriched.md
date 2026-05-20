# Silver Enriched Load Strategy (Runner)

## Ziel

Diese Doku beschreibt den aktuellen Stand des Silver-Enriched-Runners, also wie Full- und Delta-Loads gestartet werden, welche Wasserzeichen verwendet werden und welche technischen Timestamp-Felder in der Stufe wofuer da sind.

## Architektur

- Der **Runner** orchestriert die Stage `processing`, erzeugt einen Batch-Eintrag und ruft die einzelnen Steps auf.
- Ein **Step** implementiert die fachliche Verarbeitung, zum Beispiel den Text Summarizer.
- Der **DbConnector** liest die DB-Verbindung und liefert Wasserzeichen sowie Timestamp-Parsing.
- Die **Pipeline Utils** kapseln Batch-Handling, Watermark-Logik und Delta-/Target-Selektion.

## Technische Felder

Die Silver-Enriched-Stufe hat mehrere technische Timestamp-Felder, weil jede Pipeline-Phase ihren eigenen Update-Zyklus hat. Ein globales `updated_at` wuerde von nachgelagerten Schritten ueberschrieben werden und damit Watermarks verfälschen. Durch die Trennung kann jede Stage genau den Timestamp nutzen, der fuer ihren eigenen Delta-Vergleich relevant ist. Für den Processing-Run selbst setzen wir zusätzlich genau einen run-scoped `processing_update_ts` zu Beginn des Runners, damit alle Writes dieses Laufs denselben Zeitstempel erhalten und kein Reprocessing durch leicht unterschiedliche NOW()-Werte entsteht.

- `ingested_at`: Zeitpunkt des physischen Inserts in die Tabelle.
- `source_system_updated_at`: Zeitstempel aus dem Quellsystem oder der urspruenglichen Quelle.
- `preprocessing_updated_at`: Zeitpunkt, zu dem Vorverarbeitung oder Segmentierung einen Datensatz zuletzt angepasst hat.
- `processing_updated_at`: Zeitpunkt, zu dem die Processing-/Enrichment-Logik einen Datensatz zuletzt angepasst hat. Das ist das relevante Feld fuer die Gap-/Watermark-Suche in Silver Enriched.
- `batch_id`: Verknuepfung zu `pipeline_batches`, damit klar ist, mit welchem Lauf ein Datensatz geschrieben wurde.

Warum diese Aufsplittung:

- jede Stufe kann unabhaengig delta-faehig bleiben,
- spaetere Schritte ueberschreiben nicht den Zeitpunkt einer frueheren Stufe,
- Watermarks bleiben stabil und stage-spezifisch,
- NULL-Werte koennen bei Bedarf als Epoch-Fallback behandelt werden, ohne Datensaetze still zu verlieren.

## Batch-Tracking

Beim Start schreibt der Runner einen Eintrag in `pipeline_batches`.

- `stage`: fuer Silver Enriched in der Regel `processing`.
- `load_mode`: `full` oder `delta`.
- `status`: `pending`, `success` oder `failed`.
- `start_ts` und `fin_ts`: Laufzeit des Batches.

Der Batch wird beim Start angelegt und beim erfolgreichen Ende auf `success` gesetzt. Bei Fehlern oder `KeyboardInterrupt` wird er auf `failed` gesetzt.

## Watermark-Logik

- Die Watermark ist der `fin_ts` des letzten erfolgreichen Batches fuer die Stage.
- Wenn keine Historie existiert, wird auf `1970-01-01 00:00:00+00:00` zurueckgefallen.
- Ein manuelles Override ist mit `--watermark` moeglich.

## Full-Load

Im Full-Load werden alle passenden Datensaetze verarbeitet. Es findet keine Zeitfilterung statt.

## Delta-Load

Im Delta-Load werden nur Datensaetze verarbeitet, deren relevanter Processing-Zeitstempel groesser als die Watermark ist.

Fuer Silver Enriched gilt dabei:

- Kapitel-Level: bevorzugt `ch.processing_updated_at`, mit Fallbacks fuer NULL-Werte.
- Episode-Level: bevorzugt `e.processing_updated_at`.
- Podcast-Level: bevorzugt `p.processing_updated_at`.

Die Gap-/Watermark-Suche nutzt also `processing_updated_at`, nicht pauschal ein gemeinsames technisches Feld.

Wenn ein Processing-Zeitstempel `NULL` ist, wird der Datensatz nicht still ausgeschlossen, sondern wie ein sehr alter Zeitstempel behandelt. Dadurch kann der Lauf fuer diesen Datensatz wie ein Full-Load wirken oder innerhalb eines Testfensters bis zum `end_ts_watermark` mitlaufen.

## Testmodi

Testmodi sind nur aktiv, wenn `--testing` gesetzt ist.

### Testfenster

- Start: `--watermark` oder Watermark aus der DB.
- Ende: `--test-end-watermark`.
- Include-Regel: `start < source_update_ts <= end`.

### Episode-Limit

- `--test-episode-id` plus `--test-chapter-limit`.
- Es werden nur die ersten N Kapitel der angegebenen Episode verarbeitet.

Wenn `--test-end-watermark` gesetzt ist, hat das Testfenster Vorrang.

## Include- und Exclude-Regeln

- Full-Load: immer include.
- Delta-Load: include nur, wenn `source_update_ts > watermark`.
- Delta-Testfenster: include nur, wenn `watermark < source_update_ts <= test_end_watermark`.

## Aktueller Step: Text Summarizer

- Liest Kapiteltexte aus `chapter.transcript`.
- Schreibt `episodes.summary` und `chapter.summary`.

## Runner-Parameter

### Pflicht oder Kernparameter

- `--mode`: `full` oder `delta`.
- `--steps`: Komma-separierte Liste der Steps oder `processing` fuer alle Steps.
- `--stage`: Stage fuer die Watermark-Abfrage, standardmaessig `processing`.

### Wasserzeichen und Batch

- `--watermark`: ISO-Timestamp-Override fuer Delta.
- `--batch-id`: Optionaler Batch-UUID-Override.

### Testparameter

- `--testing`: Aktiviert Testparameter.
- `--test-episode-id`: Episode-ID fuer den Episode-Test.
- `--test-chapter-limit`: Maximalzahl der Kapitel fuer den Episode-Test.
- `--test-end-watermark`: Obere Watermark fuer das Testfenster.

## CLI Beispiele

### Full-Load

```bash
python src/02_processing/silver_enriched/processing_pipeline/00_pipeline_processing_runner.py \
  --mode full \
  --steps text_summarizer
```

### Delta-Load

```bash
python src/02_processing/silver_enriched/processing_pipeline/00_pipeline_processing_runner.py \
  --mode delta \
  --steps text_summarizer
```

### Delta-Testfenster

```bash
python src/02_processing/silver_enriched/processing_pipeline/00_pipeline_processing_runner.py \
  --mode delta \
  --steps text_summarizer \
  --testing \
  --watermark "2025-05-17T00:00:00+00:00" \
  --test-end-watermark "2025-05-19T12:00:00+00:00"
```

### Episode-Test

```bash
python src/02_processing/silver_enriched/processing_pipeline/00_pipeline_processing_runner.py \
  --mode full \
  --steps text_summarizer \
  --testing \
  --test-episode-id <episode_uuid> \
  --test-chapter-limit 3
```
