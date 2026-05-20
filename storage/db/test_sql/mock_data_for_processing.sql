-- =============================================================================
-- MOCK DATA – bronze / pre-enrichment test fixtures
-- Enthält: pipeline_batches, podcasts, episodes, chapter, transcript_lines
-- OHNE: embeddings, fact_checked_claims, emotion, emotion_score, summary
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. PIPELINE BATCHES
-- ---------------------------------------------------------------------------
INSERT INTO pipeline_batches (id, stage, load_mode, status, start_ts, fin_ts)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'ingestion',     'full',        'success',
   '2025-05-01 08:00:00+00', '2025-05-01 08:12:00+00'),
  ('10000000-0000-0000-0000-000000000002', 'transcription', 'delta', 'success',
   '2025-05-01 08:15:00+00', '2025-05-01 09:02:00+00'),
  ('10000000-0000-0000-0000-000000000003', 'segmenting',    'delta', 'success',
   '2025-05-01 09:05:00+00', '2025-05-01 09:28:00+00');


-- ---------------------------------------------------------------------------
-- 1. PODCASTS
-- ---------------------------------------------------------------------------
INSERT INTO podcasts (
  id, guid, feed_url, title, description, episode_count,
  categories, image_url, published_at, updated_at, batch_id,
  persons, max_episodes
) VALUES
(
  '20000000-0000-0000-0000-000000000001',
  'ki-klartext-podcast-guid-001',
  'https://feeds.example.de/ki-klartext/feed.xml',
  'KI Klartext',
  'KI Klartext beleuchtet wöchentlich die neuesten Entwicklungen in Künstlicher Intelligenz, '
  'räumt mit Mythen auf und erklärt, was wirklich hinter den Schlagzeilen steckt. '
  'Hosted von Dr. Mia Hoffmann (KI-Forscherin, TU Berlin) und Jonas Keller (Tech-Journalist).',
  48,
  ARRAY['Technology', 'Science', 'AI'],
  'https://cdn.example.de/ki-klartext/cover.jpg',
  '2023-01-15 10:00:00+00',
  '2025-04-28 10:00:00+00',
  '10000000-0000-0000-0000-000000000001',
  'Dr. Mia Hoffmann (Host, KI-Forscherin), Jonas Keller (Host, Journalist)',
  10
),
(
  '20000000-0000-0000-0000-000000000002',
  'reality-check-podcast-guid-002',
  'https://feeds.example.com/reality-check/feed.xml',
  'Reality Check',
  'Reality Check investigates viral claims, political statements, and scientific misinformation. '
  'Our team of journalists and researchers rate claims using a rigorous evidence-based framework. '
  'Hosted by Sarah Nkosi and Dr. James Ellery.',
  112,
  ARRAY['News', 'Society', 'Politics', 'Education'],
  'https://cdn.example.com/reality-check/cover.jpg',
  '2021-09-01 12:00:00+00',
  '2025-04-30 12:00:00+00',
  '10000000-0000-0000-0000-000000000001',
  'Sarah Nkosi (Host, investigative journalist), Dr. James Ellery (Host, political scientist)',
  10
);


-- ---------------------------------------------------------------------------
-- 2. EPISODES
-- ---------------------------------------------------------------------------
INSERT INTO episodes (
  id, podcast_id, guid, title, published_at, duration_seconds,
  audio_key, xml_key, transcript_key, cover_key, enclosure_url, batch_id
) VALUES
(
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'ki-klartext-ep-001-guid',
  'GPT-5 und die Wahrheit: Was Sprachmodelle wirklich können',
  '2025-04-14 06:00:00+00',
  3240,
  'audio/ki-klartext/ep001.mp3',
  'xml/ki-klartext/ep001.xml',
  'transcripts/ki-klartext/ep001.json',
  'covers/ki-klartext/ep001.jpg',
  'https://media.example.de/ki-klartext/ep001.mp3',
  '10000000-0000-0000-0000-000000000002'
),
(
  '30000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000001',
  'ki-klartext-ep-002-guid',
  'KI in der Medizin: Revolution oder Hype?',
  '2025-04-21 06:00:00+00',
  2880,
  'audio/ki-klartext/ep002.mp3',
  'xml/ki-klartext/ep002.xml',
  'transcripts/ki-klartext/ep002.json',
  'covers/ki-klartext/ep002.jpg',
  'https://media.example.de/ki-klartext/ep002.mp3',
  '10000000-0000-0000-0000-000000000002'
),
(
  '30000000-0000-0000-0000-000000000003',
  '20000000-0000-0000-0000-000000000002',
  'reality-check-ep-041-guid',
  'The Climate Numbers Politicians Get Wrong',
  '2025-04-16 07:00:00+00',
  2700,
  'audio/reality-check/ep041.mp3',
  'xml/reality-check/ep041.xml',
  'transcripts/reality-check/ep041.json',
  'covers/reality-check/ep041.jpg',
  'https://media.example.com/reality-check/ep041.mp3',
  '10000000-0000-0000-0000-000000000002'
),
(
  '30000000-0000-0000-0000-000000000004',
  '20000000-0000-0000-0000-000000000002',
  'reality-check-ep-042-guid',
  'Vaccines, Social Media, and the Myth That Won''t Die',
  '2025-04-23 07:00:00+00',
  3120,
  'audio/reality-check/ep042.mp3',
  'xml/reality-check/ep042.xml',
  'transcripts/reality-check/ep042.json',
  'covers/reality-check/ep042.jpg',
  'https://media.example.com/reality-check/ep042.mp3',
  '10000000-0000-0000-0000-000000000002'
);


-- ---------------------------------------------------------------------------
-- 3. chapter  (ohne summary)
-- ---------------------------------------------------------------------------

-- ── Episode 1 (KI Klartext – GPT-5) ──────────────────────────────────────────
INSERT INTO chapter (id, episode_id, chapter_idx, title, transcript, start_time, end_time, batch_id) VALUES
(
  '40000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001', 0,
  'Einleitung: Was wurde über GPT-5 behauptet?',
  'Jonas: Willkommen bei KI Klartext. Heute geht es um GPT-5 – das Modell, das laut OpenAI angeblich alle Benchmarks gesprengt hat. '
  'Mia, du hast die Pressemitteilung gelesen. Was war dein erster Gedanke? '
  'Mia: Mein erster Gedanke war: Welche Benchmarks genau? Denn "alle Benchmarks gesprengt" ist eine Aussage, die man sehr sorgfältig unter die Lupe nehmen muss. '
  'Jonas: Genau. Die Schlagzeile klang fast wie "KI hat das menschliche Denken übertroffen". '
  'Mia: Und das ist eben falsch. GPT-5 ist beeindruckend – aber es handelt sich um statistische Mustererkennung, nicht um Verstehen im menschlichen Sinne.',
  0, 480,
  '10000000-0000-0000-0000-000000000003'
),
(
  '40000000-0000-0000-0000-000000000002',
  '30000000-0000-0000-0000-000000000001', 1,
  'Benchmark-Analyse: MMLU, HumanEval und was sie wirklich messen',
  'Mia: Schauen wir uns den MMLU-Benchmark an. GPT-5 soll dort 92 Prozent erreicht haben. Klingt gut. '
  'Aber MMLU testet Multiple-Choice-Wissen aus 57 akademischen Disziplinen. Das heißt, das Modell wählt aus vier Optionen die richtige aus. '
  'Das ist kein Beweis für Reasoning im starken Sinne. '
  'Jonas: HumanEval ist interessanter – da geht es um Code-Generierung. Und da ist GPT-5 tatsächlich deutlich besser als sein Vorgänger. '
  'Mia: Ja, bei HumanEval sind die Verbesserungen real und messbar. Die Fehlerquote bei einfachen Algorithmen ist merklich gesunken. '
  'Jonas: Also: MMLU – PR. HumanEval – echter Fortschritt. '
  'Mia: Grob vereinfacht, aber ja.',
  480, 1560,
  '10000000-0000-0000-0000-000000000003'
),
(
  '40000000-0000-0000-0000-000000000003',
  '30000000-0000-0000-0000-000000000001', 2,
  'Halluzinationen: Warum GPT-5 immer noch lügt',
  'Jonas: Kommen wir zum Elefanten im Raum: Halluzinationen. OpenAI behauptet, die Rate sei um 50 Prozent gesunken. '
  'Mia: Das stimmt laut ihren eigenen Evaluierungen – aber die Baseline-Definition von "Halluzination" ist nicht standardisiert. '
  'Verschiedene Labs messen das verschieden. '
  'Jonas: Ich habe neulich GPT-5 nach dem Autor eines wissenschaftlichen Papers gefragt – es hat mit völliger Überzeugung einen falschen Namen genannt. '
  'Mia: Das ist das klassische Confident-Wrong-Syndrom. Das Modell lernt, selbstsicher zu klingen, nicht, korrekt zu sein. '
  'Jonas: Kann man das lösen? '
  'Mia: Retrieval-Augmented Generation hilft erheblich. Reine Generierung ohne Grounding bleibt fehleranfällig.',
  1560, 3240,
  '10000000-0000-0000-0000-000000000003'
);

-- ── Episode 2 (KI Klartext – KI in der Medizin) ──────────────────────────────
INSERT INTO chapter (id, episode_id, chapter_idx, title, transcript, start_time, end_time, batch_id) VALUES
(
  '40000000-0000-0000-0000-000000000004',
  '30000000-0000-0000-0000-000000000002', 0,
  'KI-Diagnostik in der Radiologie: Stand der Dinge',
  'Jonas: Heute haben wir Dr. Lena Brandt zu Gast, Radiologin an der Charité. Lena, wie weit ist KI in deinem Arbeitsalltag wirklich angekommen? '
  'Lena: Sie ist angekommen – aber anders als die Medien suggerieren. KI ist für mich ein zweiter Blick, kein Ersatz. '
  'Ich analysiere ein CT, die KI markiert Auffälligkeiten, und ich entscheide. '
  'Jonas: Klingt vernünftig. Mia, OpenAI und Google behaupten, ihre Modelle erkennen Lungenkrebs früher als Radiologen. '
  'Mia: In kontrollierten Studien auf bestimmten Datensätzen – ja. Im klinischen Alltag mit diversen Geräten, Patientenpopulationen und Bildqualitäten sieht das Bild deutlich gemischter aus.',
  0, 900,
  '10000000-0000-0000-0000-000000000003'
),
(
  '40000000-0000-0000-0000-000000000005',
  '30000000-0000-0000-0000-000000000002', 1,
  'FDA-Zulassungen: Zahlen und was dahintersteckt',
  'Mia: Die FDA hat seit 2020 über 500 KI-basierte Medizinprodukte zugelassen. Das klingt nach einer Revolution. '
  'Lena: Aber schau dir die Kategorien an: Der Großteil sind Bildoptimierungstools, keine diagnostischen Entscheidungssysteme. '
  'Das sind sehr unterschiedliche Risikostufen. '
  'Jonas: Also "KI in der Medizin zugelassen" ist nicht gleich "KI diagnostiziert Krankheiten". '
  'Lena: Genau. Und selbst echte Diagnosesysteme werden oft nur für sehr spezifische Indikationen zugelassen, zum Beispiel Diabetische Retinopathie-Screening. '
  'Mia: IDx-DR zum Beispiel – das erste vollständig autonome KI-Diagnosesystem überhaupt, zugelassen 2018. '
  'Das funktioniert gut in seiner engen Domäne, lässt sich aber nicht einfach generalisieren.',
  900, 1980,
  '10000000-0000-0000-0000-000000000003'
),
(
  '40000000-0000-0000-0000-000000000006',
  '30000000-0000-0000-0000-000000000002', 2,
  'Schlägt KI wirklich Ärzte? Die ehrliche Antwort',
  'Jonas: Die Frage, die alle stellen: Ist KI schon besser als Ärzte? '
  'Lena: In manchen sehr engen Aufgaben, auf den richtigen Daten: ja. Generell: nein. '
  'Und das ist keine Schwäche – kein einzelner Mensch ist in allem besser als alle Maschinen. '
  'Mia: Die Studie aus dem New England Journal of Medicine, 2023, zeigte, dass KI-Systeme bei Brustkrebsscreening '
  'mit spezialisierten Radiologen gleichziehen können – aber nicht mit dem gesamten klinischen Kontext. '
  'Jonas: Was bedeutet das für die Zukunft? '
  'Lena: Mensch plus KI schlägt beides allein. Das ist der Stand der Wissenschaft.',
  1980, 2880,
  '10000000-0000-0000-0000-000000000003'
);

-- ── Episode 3 (Reality Check – Climate Numbers) ───────────────────────────────
INSERT INTO chapter (id, episode_id, chapter_idx, title, transcript, start_time, end_time, batch_id) VALUES
(
  '40000000-0000-0000-0000-000000000007',
  '30000000-0000-0000-0000-000000000003', 0,
  'The "97% consensus" claim: true, misleading, or both?',
  'Sarah: Let''s start with the most cited number in climate discourse: 97% of scientists agree on climate change. '
  'James, is that accurate? '
  'James: It''s real, but it needs context. The figure comes from a 2013 meta-analysis by Cook et al. '
  'that reviewed nearly 12,000 peer-reviewed abstracts. Among those expressing a position on human-caused warming, 97.1% endorsed the consensus. '
  'Sarah: But critics say most papers didn''t express a position at all. '
  'James: That''s true – about two-thirds were neutral on attribution. But that doesn''t undermine the finding. '
  'The consensus on human-caused climate change is rock solid across every major scientific body on Earth.',
  0, 720,
  '10000000-0000-0000-0000-000000000003'
),
(
  '40000000-0000-0000-0000-000000000008',
  '30000000-0000-0000-0000-000000000003', 1,
  '"Renewables can''t power the grid" – fact or myth?',
  'Sarah: Claim two: "Renewable energy is too unreliable to power a modern economy." We''ve heard this from several politicians. '
  'James: This was a reasonable concern in 2005. It is increasingly not accurate in 2025. '
  'Denmark regularly generates over 100% of its electricity from wind. South Australia runs on over 70% renewables. '
  'Sarah: But what about baseload – the constant power you need at night or on windless days? '
  'James: Battery storage, interconnects, and demand management have transformed the equation. '
  'The IPCC''s 2023 report shows multiple modelled pathways to 100% clean electricity by 2050 that maintain grid stability. '
  'Sarah: So "renewables can''t power the grid" is… '
  'James: Misleading at best in 2025. Demonstrably false in several existing grids right now.',
  720, 1620,
  '10000000-0000-0000-0000-000000000003'
),
(
  '40000000-0000-0000-0000-000000000009',
  '30000000-0000-0000-0000-000000000003', 2,
  'The "it''s been warmer before" argument',
  'James: The third claim – and this one is pernicious because it contains a grain of truth: '
  '"The Earth has been warmer in the past, so current warming is natural." '
  'Sarah: I''ve heard this from three different cabinet ministers this year. '
  'James: Yes, the Earth was warmer during the Eocene, about 50 million years ago. That''s true. '
  'But that warming happened over millions of years. The current warming – about 1.2 degrees Celsius since pre-industrial times – '
  'has happened in roughly 150 years. The rate is unprecedented in the geological record. '
  'Sarah: And the cause matters. Orbital cycles drove past warmings. Today it''s CO2 from fossil fuels. '
  'James: Same destination, radically different driver, radically different speed. '
  'This argument is technically true in one narrow sense and deeply misleading in every meaningful one.',
  1620, 2700,
  '10000000-0000-0000-0000-000000000003'
);

-- ── Episode 4 (Reality Check – Vaccines & Autism) ────────────────────────────
INSERT INTO chapter (id, episode_id, chapter_idx, title, transcript, start_time, end_time, batch_id) VALUES
(
  '40000000-0000-0000-0000-000000000010',
  '30000000-0000-0000-0000-000000000004', 0,
  'The Wakefield paper: what it actually said and why it was retracted',
  'Sarah: To understand where vaccine hesitancy comes from, you have to go back to 1998 and a paper in The Lancet. '
  'James: Andrew Wakefield and twelve co-authors published a study of twelve children claiming a link between the MMR vaccine and autism. '
  'Twelve children. That''s not a study – that''s a case series. '
  'Sarah: And yet it changed the world. '
  'James: Because it was amplified by media before it could be scrutinised. '
  'The paper was retracted by The Lancet in 2010 after investigative journalist Brian Deer revealed that Wakefield had '
  'undisclosed financial conflicts of interest, manipulated data, and subjected children to unnecessary invasive procedures. '
  'Wakefield lost his medical license. '
  'Sarah: But the myth outlived the retraction by decades.',
  0, 840,
  '10000000-0000-0000-0000-000000000003'
),
(
  '40000000-0000-0000-0000-000000000011',
  '30000000-0000-0000-0000-000000000004', 1,
  'What the large-scale studies actually show',
  'James: Let''s talk about what the evidence looks like when you actually do proper epidemiology. '
  'The largest study to date is a 2019 Danish cohort study of 650,000 children. Zero association between MMR and autism. '
  'Sarah: And that''s not the only one. '
  'James: Not even close. A 2020 Cochrane review – the gold standard of evidence synthesis – analysed 138 studies covering over 23 million children. '
  'The conclusion: MMR vaccine does not cause autism. Full stop. '
  'Sarah: So why do people still believe it? '
  'James: Because autism symptoms often become apparent around the same age children receive the MMR vaccine. '
  'This is correlation, not causation – but human brains are wired to see patterns, especially around things we love, like our children.',
  840, 2040,
  '10000000-0000-0000-0000-000000000003'
),
(
  '40000000-0000-0000-0000-000000000012',
  '30000000-0000-0000-0000-000000000004', 2,
  'Social media amplification and what we can do',
  'Sarah: The question I get from listeners: why does this myth keep spreading if it''s been so thoroughly debunked? '
  'James: Social media rewards emotional content. Fear about children''s health is maximally emotional. '
  'Algorithmic amplification doesn''t distinguish between truth and falsehood – it rewards engagement. '
  'Sarah: And corrections rarely travel as far as the original claim. '
  'James: There''s research on this. A 2018 MIT study found that false news spreads six times faster on Twitter than true news. '
  'Sarah: So what''s the solution? '
  'James: Prebunking – inoculating people against misinformation before they encounter it – has shown more promise than debunking after the fact. '
  'And platform accountability matters. This isn''t just a media literacy problem.',
  2040, 3120,
  '10000000-0000-0000-0000-000000000003'
);


-- ---------------------------------------------------------------------------
-- 4. TRANSCRIPT LINES  (ohne emotion, emotion_score)
-- ---------------------------------------------------------------------------

-- ── chapter 1: Einleitung GPT-5 ──────────────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0001-000000000001', '40000000-0000-0000-0000-000000000001', 0,   0,  35,
 'Willkommen bei KI Klartext. Heute geht es um GPT-5 – das Modell, das laut OpenAI angeblich alle Benchmarks gesprengt hat.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0001-000000000002', '40000000-0000-0000-0000-000000000001', 1,  35,  90,
 'Mia, du hast die Pressemitteilung gelesen. Was war dein erster Gedanke?',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0001-000000000003', '40000000-0000-0000-0000-000000000001', 2,  90, 190,
 'Mein erster Gedanke war: Welche Benchmarks genau? "Alle Benchmarks gesprengt" ist eine Aussage, die man sehr sorgfältig unter die Lupe nehmen muss.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0001-000000000004', '40000000-0000-0000-0000-000000000001', 3, 190, 300,
 'Die Schlagzeile klang fast wie "KI hat das menschliche Denken übertroffen". Und das ist eben falsch.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0001-000000000005', '40000000-0000-0000-0000-000000000001', 4, 300, 480,
 'GPT-5 ist beeindruckend – aber es handelt sich um statistische Mustererkennung, nicht um Verstehen im menschlichen Sinne.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 2: Benchmark-Analyse ─────────────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0002-000000000001', '40000000-0000-0000-0000-000000000002', 0, 480, 600,
 'Schauen wir uns den MMLU-Benchmark an. GPT-5 soll dort 92 Prozent erreicht haben. Klingt gut.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0002-000000000002', '40000000-0000-0000-0000-000000000002', 1, 600, 780,
 'Aber MMLU testet Multiple-Choice-Wissen aus 57 akademischen Disziplinen – das Modell wählt aus vier Optionen. Das ist kein Beweis für starkes Reasoning.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0002-000000000003', '40000000-0000-0000-0000-000000000002', 2, 780, 1000,
 'HumanEval ist interessanter – da geht es um Code-Generierung. Und da ist GPT-5 tatsächlich deutlich besser als sein Vorgänger.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0002-000000000004', '40000000-0000-0000-0000-000000000002', 3, 1000, 1200,
 'Bei HumanEval sind die Verbesserungen real und messbar. Die Fehlerquote bei einfachen Algorithmen ist merklich gesunken.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0002-000000000005', '40000000-0000-0000-0000-000000000002', 4, 1200, 1560,
 'Also: MMLU – PR. HumanEval – echter Fortschritt. Grob vereinfacht, aber ja.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 3: Halluzinationen ────────────────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0003-000000000001', '40000000-0000-0000-0000-000000000003', 0, 1560, 1720,
 'OpenAI behauptet, die Halluzinations-Rate sei um 50 Prozent gesunken.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0003-000000000002', '40000000-0000-0000-0000-000000000003', 1, 1720, 1920,
 'Das stimmt laut ihren eigenen Evaluierungen – aber die Baseline-Definition von "Halluzination" ist nicht standardisiert. Verschiedene Labs messen das verschieden.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0003-000000000003', '40000000-0000-0000-0000-000000000003', 2, 1920, 2200,
 'Ich habe neulich GPT-5 nach dem Autor eines wissenschaftlichen Papers gefragt – es hat mit völliger Überzeugung einen falschen Namen genannt.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0003-000000000004', '40000000-0000-0000-0000-000000000003', 3, 2200, 2600,
 'Das ist das klassische Confident-Wrong-Syndrom. Das Modell lernt, selbstsicher zu klingen, nicht, korrekt zu sein.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0003-000000000005', '40000000-0000-0000-0000-000000000003', 4, 2600, 3240,
 'Retrieval-Augmented Generation hilft erheblich. Reine Generierung ohne Grounding bleibt fehleranfällig.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 4: Radiologie ─────────────────────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0004-000000000001', '40000000-0000-0000-0000-000000000004', 0,   0, 120,
 'Heute haben wir Dr. Lena Brandt zu Gast, Radiologin an der Charité. Lena, wie weit ist KI in deinem Arbeitsalltag wirklich angekommen?',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0004-000000000002', '40000000-0000-0000-0000-000000000004', 1, 120, 310,
 'KI ist angekommen – aber anders als die Medien suggerieren. KI ist für mich ein zweiter Blick, kein Ersatz. Ich analysiere ein CT, die KI markiert Auffälligkeiten, und ich entscheide.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0004-000000000003', '40000000-0000-0000-0000-000000000004', 2, 310, 530,
 'OpenAI und Google behaupten, ihre Modelle erkennen Lungenkrebs früher als Radiologen.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0004-000000000004', '40000000-0000-0000-0000-000000000004', 3, 530, 900,
 'In kontrollierten Studien auf bestimmten Datensätzen – ja. Im klinischen Alltag mit diversen Geräten, Patientenpopulationen und Bildqualitäten sieht das Bild deutlich gemischter aus.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 5: FDA-Zulassungen ────────────────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0005-000000000001', '40000000-0000-0000-0000-000000000005', 0, 900, 1060,
 'Die FDA hat seit 2020 über 500 KI-basierte Medizinprodukte zugelassen. Das klingt nach einer Revolution.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0005-000000000002', '40000000-0000-0000-0000-000000000005', 1, 1060, 1280,
 'Aber schau dir die Kategorien an: Der Großteil sind Bildoptimierungstools, keine diagnostischen Entscheidungssysteme. Das sind sehr unterschiedliche Risikostufen.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0005-000000000003', '40000000-0000-0000-0000-000000000005', 2, 1280, 1500,
 'IDx-DR zum Beispiel – das erste vollständig autonome KI-Diagnosesystem überhaupt, zugelassen 2018. Das funktioniert gut in seiner engen Domäne.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0005-000000000004', '40000000-0000-0000-0000-000000000005', 3, 1500, 1980,
 'Lässt sich aber nicht einfach generalisieren.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 6: KI vs. Ärzte ───────────────────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0006-000000000001', '40000000-0000-0000-0000-000000000006', 0, 1980, 2100,
 'Die Frage, die alle stellen: Ist KI schon besser als Ärzte?',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0006-000000000002', '40000000-0000-0000-0000-000000000006', 1, 2100, 2300,
 'In manchen sehr engen Aufgaben, auf den richtigen Daten: ja. Generell: nein.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0006-000000000003', '40000000-0000-0000-0000-000000000006', 2, 2300, 2580,
 'Die Studie aus dem New England Journal of Medicine, 2023, zeigte, dass KI-Systeme bei Brustkrebsscreening mit spezialisierten Radiologen gleichziehen können – aber nicht mit dem gesamten klinischen Kontext.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0006-000000000004', '40000000-0000-0000-0000-000000000006', 3, 2580, 2880,
 'Mensch plus KI schlägt beides allein. Das ist der Stand der Wissenschaft.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 7: 97% consensus ─────────────────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0007-000000000001', '40000000-0000-0000-0000-000000000007', 0,   0, 120,
 'Let''s start with the most cited number in climate discourse: 97% of scientists agree on climate change. James, is that accurate?',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0007-000000000002', '40000000-0000-0000-0000-000000000007', 1, 120, 320,
 'It''s real, but it needs context. The figure comes from a 2013 meta-analysis by Cook et al. that reviewed nearly 12,000 peer-reviewed abstracts.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0007-000000000003', '40000000-0000-0000-0000-000000000007', 2, 320, 480,
 'Among those expressing a position on human-caused warming, 97.1% endorsed the consensus.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0007-000000000004', '40000000-0000-0000-0000-000000000007', 3, 480, 600,
 'About two-thirds of papers were neutral on attribution. But that doesn''t undermine the finding.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0007-000000000005', '40000000-0000-0000-0000-000000000007', 4, 600, 720,
 'The consensus on human-caused climate change is rock solid across every major scientific body on Earth.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 8: Renewables ─────────────────────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0008-000000000001', '40000000-0000-0000-0000-000000000008', 0, 720, 900,
 '"Renewable energy is too unreliable to power a modern economy." We''ve heard this from several politicians.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0008-000000000002', '40000000-0000-0000-0000-000000000008', 1, 900, 1100,
 'This was a reasonable concern in 2005. It is increasingly not accurate in 2025. Denmark regularly generates over 100% of its electricity from wind.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0008-000000000003', '40000000-0000-0000-0000-000000000008', 2, 1100, 1350,
 'Battery storage, interconnects, and demand management have transformed the equation. The IPCC''s 2023 report shows multiple modelled pathways to 100% clean electricity by 2050.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0008-000000000004', '40000000-0000-0000-0000-000000000008', 3, 1350, 1620,
 'Misleading at best in 2025. Demonstrably false in several existing grids right now.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 9: It's been warmer before ───────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0009-000000000001', '40000000-0000-0000-0000-000000000009', 0, 1620, 1820,
 '"The Earth has been warmer in the past, so current warming is natural." I''ve heard this from three different cabinet ministers this year.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0009-000000000002', '40000000-0000-0000-0000-000000000009', 1, 1820, 2060,
 'Yes, the Earth was warmer during the Eocene, about 50 million years ago. That''s true. But that warming happened over millions of years.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0009-000000000003', '40000000-0000-0000-0000-000000000009', 2, 2060, 2350,
 'The current warming – about 1.2 degrees Celsius since pre-industrial times – has happened in roughly 150 years. The rate is unprecedented in the geological record.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0009-000000000004', '40000000-0000-0000-0000-000000000009', 3, 2350, 2700,
 'Orbital cycles drove past warmings. Today it''s CO2 from fossil fuels. Same destination, radically different driver, radically different speed.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 10: Wakefield ─────────────────────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0010-000000000001', '40000000-0000-0000-0000-000000000010', 0,   0, 140,
 'Andrew Wakefield and twelve co-authors published a study of twelve children claiming a link between the MMR vaccine and autism.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0010-000000000002', '40000000-0000-0000-0000-000000000010', 1, 140, 300,
 'Twelve children. That''s not a study – that''s a case series.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0010-000000000003', '40000000-0000-0000-0000-000000000010', 2, 300, 520,
 'The paper was retracted by The Lancet in 2010 after it was revealed that Wakefield had undisclosed financial conflicts of interest and manipulated data.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0010-000000000004', '40000000-0000-0000-0000-000000000010', 3, 520, 700,
 'Wakefield lost his medical license.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0010-000000000005', '40000000-0000-0000-0000-000000000010', 4, 700, 840,
 'But the myth outlived the retraction by decades.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 11: Large-scale vaccine studies ───────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0011-000000000001', '40000000-0000-0000-0000-000000000011', 0,  840, 1020,
 'The largest study to date is a 2019 Danish cohort study of 650,000 children. Zero association between MMR and autism.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0011-000000000002', '40000000-0000-0000-0000-000000000011', 1, 1020, 1280,
 'A 2020 Cochrane review analysed 138 studies covering over 23 million children. The conclusion: MMR vaccine does not cause autism. Full stop.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0011-000000000003', '40000000-0000-0000-0000-000000000011', 2, 1280, 1600,
 'Autism symptoms often become apparent around the same age children receive the MMR vaccine. This is correlation, not causation.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0011-000000000004', '40000000-0000-0000-0000-000000000011', 3, 1600, 2040,
 'Human brains are wired to see patterns, especially around things we love, like our children.',
 '10000000-0000-0000-0000-000000000003');

-- ── chapter 12: Social media ──────────────────────────────────────────────────
INSERT INTO transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, batch_id) VALUES
('50000000-0000-0000-0012-000000000001', '40000000-0000-0000-0000-000000000012', 0, 2040, 2220,
 'Why does this myth keep spreading if it''s been so thoroughly debunked?',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0012-000000000002', '40000000-0000-0000-0000-000000000012', 1, 2220, 2480,
 'Social media rewards emotional content. Fear about children''s health is maximally emotional. Algorithmic amplification doesn''t distinguish between truth and falsehood – it rewards engagement.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0012-000000000003', '40000000-0000-0000-0000-000000000012', 2, 2480, 2720,
 'A 2018 MIT study found that false news spreads six times faster on Twitter than true news.',
 '10000000-0000-0000-0000-000000000003'),
('50000000-0000-0000-0012-000000000004', '40000000-0000-0000-0000-000000000012', 3, 2720, 3120,
 'Prebunking – inoculating people against misinformation before they encounter it – has shown more promise than debunking after the fact. Platform accountability matters too.',
 '10000000-0000-0000-0000-000000000003');


-- ---------------------------------------------------------------------------
-- DONE
-- Zusammenfassung:
--   pipeline_batches  :  3  (ingestion, transcription, chaptering)
--   podcasts          :  2
--   episodes          :  4
--   chapter          : 12
--   transcript_lines  : 53  (4–5 pro chapter, alle 12 chaptere befüllt)
-- ---------------------------------------------------------------------------
