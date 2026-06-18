--
-- PostgreSQL database dump
--


-- Dumped from database version 16.13 (Debian 16.13-1.pgdg12+1)
-- Dumped by pg_dump version 16.13 (Debian 16.13-1.pgdg12+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: batch_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.batch_status AS ENUM (
    'pending',
    'success',
    'failed',
    'consumed',
    'stopped'
);


--
-- Name: embedding_level; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.embedding_level AS ENUM (
    'chapter',
    'episode',
    'podcast'
);


--
-- Name: emotion_label; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.emotion_label AS ENUM (
    'happy',
    'neutral',
    'angry',
    'sad'
);


--
-- Name: fact_verdict; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.fact_verdict AS ENUM (
    'TRUE',
    'MOSTLY_TRUE',
    'MISLEADING',
    'FALSE',
    'UNVERIFIABLE'
);


--
-- Name: load_mode; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.load_mode AS ENUM (
    'full',
    'delta'
);


--
-- Name: pipeline_stage; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.pipeline_stage AS ENUM (
    'ingestion',
    'transcription',
    'segmenting',
    'text_summarizer',
    'emotion_scoring',
    'embedder',
    'fact_checker'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: chapters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chapters (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    episode_id uuid NOT NULL,
    chapter_idx integer NOT NULL,
    title text,
    transcript text,
    summary text,
    start_time real NOT NULL,
    end_time real NOT NULL,
    batch_id uuid,
    preprocessing_updated_at timestamp with time zone DEFAULT now() NOT NULL,
    processing_updated_at timestamp with time zone,
    CONSTRAINT ck_chapters_chapter_idx CHECK ((chapter_idx >= 0)),
    CONSTRAINT ck_chapters_end_time CHECK ((end_time >= (0)::double precision)),
    CONSTRAINT ck_chapters_start_time CHECK ((start_time >= (0)::double precision)),
    CONSTRAINT ck_chapters_time_range CHECK ((end_time >= start_time))
);


--
-- Name: embeddings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.embeddings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chapter_id uuid,
    episode_id uuid,
    podcast_id uuid,
    level public.embedding_level NOT NULL,
    embedding public.halfvec(2560),
    batch_id uuid,
    processing_updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT embeddings_level_fk_check CHECK ((((level = 'podcast'::public.embedding_level) AND (podcast_id IS NOT NULL) AND (episode_id IS NULL) AND (chapter_id IS NULL)) OR ((level = 'episode'::public.embedding_level) AND (episode_id IS NOT NULL) AND (podcast_id IS NULL) AND (chapter_id IS NULL)) OR ((level = 'chapter'::public.embedding_level) AND (chapter_id IS NOT NULL) AND (podcast_id IS NULL) AND (episode_id IS NULL))))
);


--
-- Name: episodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.episodes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    podcast_id uuid NOT NULL,
    guid text NOT NULL,
    title text NOT NULL,
    published_at timestamp with time zone,
    duration_seconds integer,
    audio_key text NOT NULL,
    xml_key text,
    transcript_key text,
    cover_key text,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    source_system_updated_at timestamp with time zone DEFAULT now() NOT NULL,
    processing_updated_at timestamp with time zone,
    preprocessing_updated_at timestamp with time zone,
    ingestion_updated_at timestamp with time zone DEFAULT now() NOT NULL,
    enclosure_url text,
    summary text,
    batch_id uuid,
    CONSTRAINT ck_episodes_duration_seconds CHECK (((duration_seconds IS NULL) OR (duration_seconds >= 0)))
);


--
-- Name: fact_checked_claims; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_checked_claims (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chapter_id uuid NOT NULL,
    claim_idx integer,
    claim text,
    verdict public.fact_verdict DEFAULT 'UNVERIFIABLE'::public.fact_verdict,
    explanation text,
    sources text[],
    batch_id uuid,
    processing_updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_fact_checked_claims_claim_idx CHECK ((claim_idx >= 0))
);


--
-- Name: pipeline_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pipeline_batches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    stage public.pipeline_stage NOT NULL,
    load_mode public.load_mode NOT NULL,
    status public.batch_status DEFAULT 'pending'::public.batch_status NOT NULL,
    start_ts timestamp with time zone DEFAULT now() NOT NULL,
    fin_ts timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_pipeline_batches_time_range CHECK ((fin_ts >= start_ts))
);


--
-- Name: podcasts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.podcasts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    guid text NOT NULL,
    hosts text,
    feed_url text NOT NULL,
    title text NOT NULL,
    description text,
    episode_count integer,
    categories text[],
    image_url text,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    published_at timestamp with time zone,
    batch_id uuid,
    source_system_updated_at timestamp with time zone,
    processing_updated_at timestamp with time zone,
    preprocessing_updated_at timestamp with time zone,
    ingestion_updated_at timestamp with time zone DEFAULT now() NOT NULL,
    max_episodes integer,
    CONSTRAINT ck_podcasts_episode_count CHECK (((episode_count IS NULL) OR (episode_count >= 0))),
    CONSTRAINT ck_podcasts_max_episodes CHECK (((max_episodes IS NULL) OR (max_episodes >= 0)))
);


--
-- Name: transcript_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transcript_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chapter_id uuid NOT NULL,
    line_idx integer NOT NULL,
    start_time real NOT NULL,
    end_time real NOT NULL,
    text text NOT NULL,
    emotion public.emotion_label DEFAULT 'neutral'::public.emotion_label,
    emotion_score real,
    batch_id uuid,
    processing_updated_at timestamp with time zone,
    preprocessing_updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_transcript_lines_emotion_score CHECK (((emotion_score IS NULL) OR ((emotion_score >= (0)::double precision) AND (emotion_score <= (1)::double precision)))),
    CONSTRAINT ck_transcript_lines_line_idx CHECK ((line_idx >= 0)),
    CONSTRAINT ck_transcript_lines_start_time CHECK ((start_time >= (0)::double precision))
);


--
-- Data for Name: chapters; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chapters (id, episode_id, chapter_idx, title, transcript, summary, start_time, end_time, batch_id, preprocessing_updated_at, processing_updated_at) FROM stdin;
f9cbfe5d-ef47-4411-88b7-1626bd5c821d	965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	0	Technology	Life doesn't always come with a pause button. There's always something pulling your attention, someone asking for more. Most days you're just moving through, trying to keep up. As the to-do list gets longer, you don't always realize how much your mind is caring. It's easy to forget to check in without you really doing. But headspace can help. Now headspace works with your Apple Watch to support your mind when your body says you need it. This mental health awareness month tap into what your mind needs. Now that headspace works with Apple Watch, you can meditate on a walk, take a breath during a meeting, or stay calm while sitting in traffic, all without using your phone screen. And throughout your day, headspace sends gentle nudges to your Apple Watch with quick breathing	\N	0	50	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:18:58.729478+00	\N
c5e25575-2b26-4922-b0e3-47f43e425c13	965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	1	Parenting	exercises to help you relax. A breath at the right time can change your entire day. Go to headspace.com to start your free trial today. Hi, it's Andy here, and welcome to Radio Headspace, until the start of the week, Monday morning. Now you may already have kids, you may not have them yet, but if you could teach your kids just one valuable lesson, the most valuable lesson that you think they would benefit from in their life, what would it be?	\N	50	93	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:18:58.729478+00	\N
20d73e1a-b024-416e-9710-69e30acf0a0a	965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	2	Opinion	You know, I have some friends who believe the most important thing is that their child feels loved. No matter what else happens, that's the most important thing, that's the most valuable lesson. Now have another friend who thinks it's honesty, he always says to his son, you know, I don't care what you do as long as you tell me the truth. That is the most important thing in life. And a friend asked me the other day, what would I teach my son or do I try to teach	\N	94	119	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:18:58.729478+00	\N
7da0e586-1f05-4ed2-9592-37db3933a831	965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	3	Opinion	my son's? But when my son sits still for long enough to actually listen to me, you know, I will always come back to the four foundations that were taught to me at the beginning of the monastery. I genuinely have found them the most useful things. I've still find them useful to this day, and because they're not beliefs, because they're just sort of fundamental truths in life, we can't really avoid them, we'll find	\N	119	142	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:18:58.729478+00	\N
b57fa5d6-7694-45b5-8914-f43d82105f7f	965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	4	General	them in every part of our life. And even when one doesn't connect or relate, you can always sort of lean on another of the four. So I'm cheating a little bit, it's not just one thing, it's four things. But I thought it's shared them with you. The first one is this idea of a precious human life, the idea that, you know, we might take life for granted, especially when things aren't going our way, when we're not enjoying life perhaps, there is a sense of taking it for granted. We don't appreciate just how precious it is.	\N	142	172	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:18:58.729478+00	\N
4dd363c8-39ef-453c-9beb-05c74366dba2	965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	5	General	And it often takes perhaps the death of a loved one or a close friend or something that really, really shocks us to cut through that chatter in the mind, to get us to a point where we realise just how fortunate we are to be alive and to recognise those things that are going well. So that's the first one, I feel like that's just useful on any given day. The second one is the impermanence, the idea of change. Most of our life we are sort of fighting change, I think. Although we might have an idea that, oh, you know, with someone that enjoys change, and we might thrive as a result of it, think fundamentally, we assume in beings we like the idea of safety and security and comfort, change can feel almost sort of threatening	\N	172	217	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:18:58.729478+00	\N
18b04d89-6ab0-43b2-b945-9d326e64a688	965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	6	General	in some ways. And even in the mind, we might struggle with the idea that things are always changing. We might try to hold on to the things that we like and we might try and resist the things that we don't like. But once we accept that change is all around us, internally and externally, there is nothing to hold on to and equally there is nothing to fear because everything is changing all of the time. The third one's cause and effect, although we know this intellectually, I think very often	\N	217	247	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:18:58.729478+00	\N
ddfc2e09-e96f-4f29-963a-d9d2c7380b71	965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	7	General	in life we don't live our lives this way. Everything that we do has some kind of impact and very often in life we will continue to do the same things that lead to a somewhat negative outcome or say the same things that lead to a negative outcome without really acknowledging the cause of that. But once we start to see that and recognize it, it makes no sense to do those things, to repeat those things. So once we have enough awareness and clarity around those, we have the opportunity to choose a different course of action. Feel like that one's especially useful for kids who are still very much in the mode of discovering what leads to a good outcome and what leads to a less good outcome. The final one is a sense of acceptance and I don't mean acceptance in the sense of just	\N	247	293	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:18:58.729478+00	\N
ed3af611-6a74-44ce-baba-fbbf9391ff17	965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	8	General	letting things be as they are, to some things need to change and it's good to have clarity around what needs to change. But there's also sort of a broader acceptance that in life, life is a mixture. There's not just happiness, we may strive for eternal happiness for this idea that we will be happy all of the time if we can just work things out in a certain way.	\N	293	318	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:18:58.729478+00	\N
274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	9	Opinion	Life's way more complicated than that and if we can come to terms with the fact that sometimes life is stressful, sometimes life is difficult, sometimes life is painful and that those things aren't wrong as much as we may not like the circumstances or situation at the time. If we can work with them and change our relationship with them, then at least internally in those very difficult situations where we would have a greater sense of calm and clarity, so we can actually deal with them in a more constructive way. Throughout my life I found those four things incredibly helpful. So if I had to choose just one thing or one group of things to teach my children, it would be that. And the truth is, this is about kids but it's not about kids. This is just another way of asking ourselves, what's most important in our life? And if we have to remember just one thing, what would that one thing be? Have a great day today, have a great week this week, thanks for listening and I'll see you back here tomorrow.	\N	318	375	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:18:58.729478+00	\N
29937f7d-c2b6-4419-9244-fc66d522a2e6	c1492e6f-9fed-415c-b0ad-306ec03030b8	0	Technology	Life doesn't always come with a pause button. There's always something pulling your attention, someone asking for more. Most days you're just moving through, trying to keep up. As the to-do list gets longer, you don't always realize how much your mind is caring. It's easy to forget to check in without you really doing. But headspace can help. Now headspace works with your Apple Watch to support your mind when your body says you	\N	0	27	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:04.170762+00	\N
c248131e-3738-495d-b166-ff454577bcc5	c1492e6f-9fed-415c-b0ad-306ec03030b8	1	Technology	need it. This mental health awareness month tap into what your mind needs. Now that headspace works with Apple Watch, you can meditate on a walk, take a breath during a meeting, or stay calm while sitting in traffic, all without using your phone screen. And throughout your day, headspace sends gentle nudges to your Apple Watch with quick breathing exercises to help you relax. A breath at the right time can change your entire day.	\N	27	56	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:04.170762+00	\N
258bf44b-679e-41e5-be28-944a6935c5f4	c1492e6f-9fed-415c-b0ad-306ec03030b8	2	Arts	Go to headspace.com to start your free trial today. Hi, it's Andy here, and welcome to Radioheadspace. And to the end of the week, Friday morning. I'd like you to take a moment today, just to think about the ways that you express creativity	\N	56	81	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:04.170762+00	\N
83c59de5-4f13-4e46-8df2-c743fdff4b92	c1492e6f-9fed-415c-b0ad-306ec03030b8	3	Leisure	in your life. Maybe it's in your work, maybe it's in your spare time, maybe it's in the way that you present yourself to the world. There are so many different ways of expressing creativity. And it's interesting, as we grow up over time, how those expressions change, and maybe the intention and purpose behind them change, and how that even begins to influence the expression itself. So how do we get back to that real innocence, expressing creativity in a way that is without	\N	81	109	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:04.170762+00	\N
896b424e-9fb5-45eb-846d-d0a3edf4ea41	c1492e6f-9fed-415c-b0ad-306ec03030b8	4	Commodities	any purpose, without any reason, without any expectation. And it's interesting, you think maybe sort of with children that they might do that, but I willing to experiment a lot, and there may be not making it necessarily with the intention to get approval at the same time. There is definitely an idea having expressed that thing, to then sort of seek approval for it and to feel better as a consequence. As we get older, I think often commerce comes into play, and especially if it's for our work,	\N	109	143	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:04.170762+00	\N
75a983b7-97b7-49dc-9656-fdb4f0b12f36	c1492e6f-9fed-415c-b0ad-306ec03030b8	5	Business	we feel the need. There is a very real need to actually make something that other people like. So all of a sudden, I think the expression starts to be manipulated in some ways. Of course, when it comes to commerce and a work, there's no real way around that. That's kind of as it is, and we have to find a way in our own mind to be okay with that. But I feel it's really important in everyday life to find some way, some play, somehow, of simply expressing ourselves in a way that feels innocent and uncontrived,	\N	143	180	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:04.170762+00	\N
85514b58-5cea-42da-ac15-630d53843a98	c1492e6f-9fed-415c-b0ad-306ec03030b8	6	Language	and the feels that brings a sense of joy to our life. It's so easy, I think, to focus on what other people like. And in doing that, we are already moving away from that expression. To be able to genuinely deliver something without any idea, without any expectation,	\N	181	201	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:04.170762+00	\N
19c59c3b-6c17-432a-8d6d-f169d9755e2a	c1492e6f-9fed-415c-b0ad-306ec03030b8	7	Music	without wanting to impress another person. As she takes real courage, it's quite difficult. Now you may be thinking, well, this is crazy. I'm not going to sort of cook up a huge dinner for friends and invite them around and not care whether they like it or not. Or I'm not going to, I don't know, learn a new tune on my guitar or piano or whatever and play it for someone else and not care what they think. But actually finding areas of life where the risk is fairly low, I think is really important. It reminds us of something, I think quite different is very hard to find that in other areas of life,	\N	202	235	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:04.170762+00	\N
1ce986ce-65d4-4d7f-8adc-0af66b7f60ca	c1492e6f-9fed-415c-b0ad-306ec03030b8	8	Language	where we have the freedom to truly express how we feel, but without any real consequence. And hey, look, we don't have to start by doing it in front of others. It might be that we begin on our own just getting comfortable with the idea, and then maybe we share it with someone. And maybe it's something they like, maybe it's something they don't like. Working with that, even if we perceive it as negative feedback, as she allows us to grow in confidence, to grow in courage, and to get back a little bit closer to that idea of a natural expression of creativity. There's something to think about over the weekend, whatever you're doing, I hope you have a wonderful weekend, I'll look forward to seeing you back here on Monday.	\N	236	278	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:04.170762+00	\N
5c4432d1-4541-4b93-b3d9-52822f72f400	3b4e2a60-3d08-4d47-9aff-751d2125d95b	0	Technology	Life doesn't always come with a pause button. There's always something pulling your attention, someone asking for more. Most days you're just moving through, trying to keep up. As the to-do list gets longer, you don't always realize how much your mind is caring. It's easy to forget to check in without you really doing. But headspace can help. Now headspace works with your Apple Watch to support your mind when your body says you	\N	0	27	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:07.57476+00	\N
a5ed8b96-7712-49cb-9e4b-d83b52f116a7	3b4e2a60-3d08-4d47-9aff-751d2125d95b	1	Technology	need it. This mental health awareness month tap into what your mind needs. Now that headspace works with Apple Watch, you can meditate on a walk, take a breath during a meeting, or stay calm while sitting in traffic, all without using your phone screen. And throughout your day, headspace sends gentle nudges to your Apple Watch with quick breathing exercises to help you relax. A breath at the right time can change your entire day.	\N	27	56	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:07.57476+00	\N
81a01dfa-9fa3-426e-8ea1-1577e38a67e2	3b4e2a60-3d08-4d47-9aff-751d2125d95b	2	General	Go to headspace.com to start your free trial today. Hi, it's Andy here, and welcome to Radioheadspace, until Wednesday morning. So I wonder if there's a part of you that you would like to change. For most of us, I think there are aspects of ourselves that we might wish were a little different.	\N	56	89	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:07.57476+00	\N
05da32ac-f08c-4846-bdfe-f07d36f2a517	3b4e2a60-3d08-4d47-9aff-751d2125d95b	3	Health	And sometimes there might be a feeling as though it's impossible to change. And the older we get, we might assume that, well, the longer we've been alive, the more solid those qualities become, and therefore, the less likely it is to change. But to that, I'd like to kind of reframe that a little differently. And maybe offer a dilemma of hope that we can change at any age. And look, I say this is not only someone who's getting on in the years, but, you know, we've had people along at headspace in their 70s, 80s and 90s learning meditation and talking about how even at that age, it's really transformed their thinking the way they feel about themselves and about particular aspects of themselves. And I'm always fascinated by this idea of impermanence and change and how everything is in constant flux, all of the time. If we think about the physical body, for example, okay, so more than I don't know exactly how many, but I know there's more	\N	90	150	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:07.57476+00	\N
82e32b6a-c531-4f20-aa02-50c8008aa055	3b4e2a60-3d08-4d47-9aff-751d2125d95b	4	General	30 trillion cells in the body and that those cells are refreshed, replaced in full every six months. Something like that, we're going to sort of a cycle. So even though we look at our physical body and we might assume that it is solid, that it's fixed, that it kind of is what it is. Well, in truth, the entire physical body is being refreshed and replenished over that period of time. So then we might think, yeah, sure, but what about our thoughts and our mind? That's always the same. Well, if meditation teaches us anything, mindfulness teaches us anything. It's that the mind is never the same. Sure, we might have the same similar sort of theme thoughts that come back time and time again,	\N	150	194	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:07.57476+00	\N
206c85d1-07dd-48f5-ad47-098ecab12ae1	3b4e2a60-3d08-4d47-9aff-751d2125d95b	5	Environment	but it's never the same thought. It might sound identical in the mind. It may look identical in the mind, but it's always within a different environment because the mind is constantly changing. So if we're able to witness that clearly in our mind and see that thoughts are always changing, feelings are always changing, that our body is always changing, and that our place in the world is	\N	194	218	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:07.57476+00	\N
d60ca940-a5b9-4102-ad2e-046cab6fc2c3	3b4e2a60-3d08-4d47-9aff-751d2125d95b	6	Opinion	always changing, then all of a sudden things don't feel so fixed, that don't feel so static. There's a feeling, even if it's just a little bit, of freedom, of movement, offering us the possibility and the potential for change. So as you go into your day to day, as you go into the rest of the week, just maintaining that idea, that there is perhaps a lot more freedom in our mind, in our body, and in our life than when we often like to think. Thanks for listening today. I look forward to seeing you back here tomorrow.	\N	218	252	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:07.57476+00	\N
eaade9c7-162b-4191-9849-41bcce1db700	ed61d48f-1a11-4d2b-988c-da9d203496fa	0	General	Hey everybody, welcome back for another episode of the five-minute Disoppoship podcast. My name is Lauren Higgs and on this podcast I share five-minute episodes to help you grow in your faith. This podcast is about discipleship and spiritual growth. It's my prayer that the short episodes inspire you and encourage you to be a fully devoted follower of Jesus Christ. So if you're new to the podcast let me invite you to subscribe on your favorite podcast app	\N	5	36	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:10.924563+00	\N
8143135c-7e6b-49ee-b881-f93fe8e8a45d	ed61d48f-1a11-4d2b-988c-da9d203496fa	1	Opinion	so that you can join us each day. Today on the podcast we are talking about when God stands beside you. It's been said that a real friend is one who walks in when the rest of the world walks out. Have you ever had a friend like that? Perhaps you had a season in your life when it felt as if everyone was against you and that you were all alone. Proverbs chapter 18 verse 24 says there is a friend who sticks closer than a brother. I want you to know Jesus is that friend.	\N	36	71	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:10.924563+00	\N
db0f8227-6589-48fe-8872-2ca1431234db	ed61d48f-1a11-4d2b-988c-da9d203496fa	2	History	When everyone leaves, when you feel abandoned and when there is no one else around, God will remain present in your life. In fact, he has promised in scripture that he will never leave us, nor forsake us. You know, in second Timothy chapter 4 the apostle Paul is writing about his defense of the gospel as a prisoner in Rome. He talks about how everyone abandoned him and he was left alone as he stood before the Roman authorities. This reminds me of how the disciples of Jesus fled after his arrest. But listen to what Paul says, second Timothy chapter 4 verse 16 and 17. At my first defense no one came to my support, but everyone deserted me. May it not be held against them, but the Lord stood at my side and gave me strength. So that through me the message might be fully proclaimed and all the Gentiles might hear it. How discouraging it must have been for Paul that not even his closest friends would be with him, during one of his most difficult days.	\N	72	134	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:10.924563+00	\N
143f1bf0-cc19-4f8d-b26c-ea90908b06b2	ed61d48f-1a11-4d2b-988c-da9d203496fa	3	General	Yet Paul acknowledges the presence of God. He said the Lord stood at my side and gave me strength. All he had was God, but that was all he needed. Like the apostle Paul, you might be facing one of your most difficult situations. Maybe you are facing it all alone and you wonder where your family and friends are. Perhaps it seems that no one understands.	\N	134	156	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:10.924563+00	\N
448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	ed61d48f-1a11-4d2b-988c-da9d203496fa	4	Opinion	How want you to receive this truth today? God is standing beside you. He is there. Can you acknowledge his presence? Everything you need he will provide. Repeatedly in the Bible he promises us that he will be with us. Listen to Isaiah chapter 41 verse 10. The Bible says, don't be afraid for I am with you. Don't be discouraged for I am your God. I will strengthen you and help you. I will hold you up with my victorious right hand. In Deuteronomy chapter 31 verse 8 says, Do not be afraid or discouraged for the Lord will personally go ahead of you. He will be with you. He will neither fail nor abandon you. What I love about the Bible are the real-life stories of people who faced all kinds of difficulty and adversity. We learn of their struggles spiritually, emotionally, and physically. But we also see God at work in their lives.	\N	157	213	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:10.924563+00	\N
f508a024-399c-4333-89af-2c98e3411cf9	ed61d48f-1a11-4d2b-988c-da9d203496fa	5	Opinion	We learn of God's faithfulness. We see God's compassion, wisdom, and guidance. We discover he is a God who loves his people and one who will never abandon them. You know, in my own life it is the presence of Jesus that has made such a difference. Had I faced my battles alone?	\N	213	232	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:10.924563+00	\N
c1822876-0f14-4cb4-a279-b379115292a8	ed61d48f-1a11-4d2b-988c-da9d203496fa	6	Opinion	I don't know how I could have survived, but I can say like the Apostle Paul, the Lord stood at my side and gave me strength. Perhaps today you are facing a physical illness. Maybe you are stuck at home in a hospital or a nursing home and you feel all alone. Possibly you are dealing with merit of conflict or abandonment by your children. Maybe you feel beaten down by financial struggles overwhelmed by stress at work or anxious about your future. Receive this encouragement. God is standing at your side and he will give you strength. There is nothing you are facing that God cannot handle. There is no need in your life. God cannot meet. There are no problems. God cannot solve. The eternal God is standing beside you right now. And here's today's challenge. Set aside a few minutes to acknowledge God's faithful presence in your life. Thank you that he has always been with you and that he always will be. Hey, thanks again for joining me for today's episode. I hope you have a wonderful day. And until next time, let's continue on our journey as followers of Jesus.	\N	232	304	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:10.924563+00	\N
06234d44-36df-41e1-84c8-8b8530cd72f3	0e3e6c19-5048-46e8-a206-1b51865c0f62	0	Opinion	Hey everybody, welcome back for another episode of the five-minute discipleship podcast. My name is Lauren Hicks, and on this podcast, I share five-minute episodes to help you grow in your faith. This podcast is about discipleship and spiritual growth. It's my prayer that these short episodes inspire you and encourage you to be a fully devoted follower of Jesus Christ. So if you're new to the podcast, let me invite you to subscribe on your favorite podcast	\N	5	34	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:14.997582+00	\N
325015cb-4dc6-4683-9d20-921e2e1a1266	0e3e6c19-5048-46e8-a206-1b51865c0f62	1	Opinion	app so that you can join us each day. Today on the podcast, we are talking about the ministry of encouragement. Early in my ministry, as I pastor to small church in West Texas, my wife and I met an elderly woman named Thelma. She was now laid in life, but had served God since she was a child. While she did not attend our church, she felt called by God to be a blessing to my wife and I. We were in our 20s, pasturing our first church, and by divine appointment, God connected us to this precious woman. Throughout our years at the church, she fulfilled her calling by being an encouraged	\N	34	76	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:14.997582+00	\N
730b38f5-355f-48b9-937d-f10e19cf0492	0e3e6c19-5048-46e8-a206-1b51865c0f62	2	Religion	your to my wife and I. She would often invite us over for dinner, pray for us, and share words of encouragement the Lord had given her. I cannot tell you what a blessing this woman of God was to my family. I can't remember a time being in her presence that I was not encouraged. Have you ever had an encourager in your life? Someone that whenever you were around them, you found your spirit lifted. This is the kind of person I want to be. I want to be an encourager. You know, in the New Testament, there is a man named Barnabas. He was a leader in the early church and a partner with the Apostle Paul on some of his missionary journeys. But we learned something important about him in Acts 4 verse 36, which says, Joseph a Levi from Cyprus whom the Apostles called Barnabas, which means son of encouragement. His real name was Joseph, but he was given a nickname by the Apostles.	\N	76	133	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:14.997582+00	\N
ab57e0ee-1415-4b89-b057-6cd5710f20c3	0e3e6c19-5048-46e8-a206-1b51865c0f62	3	Religion	They called him Barnabas, which meant son of encouragement. He was affectionately given this nickname because he had the ministry of encouragement. As we read the book of Acts, we see that Barnabas was an early disciple in the New Testament church. He was a Levi from Cyprus and island in the Mediterranean Sea about 60 miles off the coast of Israel. Barnabas later visited the island of Cyprus on the first missionary journey with the	\N	133	161	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:14.997582+00	\N
6c105bc0-178a-46d9-a1ed-2c987616ae18	0e3e6c19-5048-46e8-a206-1b51865c0f62	4	History	Apostle Paul and again on a second journey with Mark. When Barnabas became a Christian, he sold his land and gave the money to the Jerusalem Apostles. Early in the history of the church, he went to Anniac to check on the growth of the Christians there and then on to Tarsus. From there, he brought Saul, later named Paul, back to Anniac to help with the church in that city, which was the third largest in the Mediterranean world. Think about the influence and impact of this one man.	\N	161	190	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:14.997582+00	\N
d61399a3-e22c-465d-b45d-4ccf0c270667	0e3e6c19-5048-46e8-a206-1b51865c0f62	5	Christianity	With a huge heart for God and people, Barnabas finds Saul believing that God has a plan for his life. He brings him to Anniac and includes him in the ministry of the local church. Saul later becomes the Apostle Paul who would plant churches all across Asia Minor and would write two thirds of the New Testament. So let's think about this. What if Barnabas had not been an encourager? What if he had not obey God to reach out to Saul? You never know the impact of your kindness, your love and your words of encouragement. I believe people around you today are desperate for encouragement.	\N	190	227	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:14.997582+00	\N
afe359a4-a5a9-4c34-a59d-fb014f9f2f92	0e3e6c19-5048-46e8-a206-1b51865c0f62	6	Opinion	Everyone around you is fighting about it, you know nothing about. What if difference you could make in someone's life by encouraging them to trust the Lord to keep believing and to not give up? What if difference you could make by encouraging someone to obey God to step out and faith and to let God use their lives? First, that's Elonian chapter 5 verse 11 says, encourage one another and build each other up. Hebrews chapter 10 verses 24 and 25 say, let us think of ways to motivate one another to acts of love and good works. And let us not neglect our meeting together as some people do, but encourage one another, especially now that the day of his return is drawing near. And here's today's challenge. I believe every believer has a ministry. Don't overlook the importance of being an encourager. It cost you nothing but your love, your kindness, and your time. Hey, thanks again for joining me for today's episode. I hope you have a wonderful day and until next time, let's continue on our journey as followers of Jesus.	\N	228	295	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:14.997582+00	\N
af85381a-ffa7-4b6d-9e6d-b0efe88423e6	d2127ddc-5a10-420e-b754-2dfa51975b3a	0	Opinion	Hey everybody, welcome back for another episode of the Five Minute Disoppership podcast. My name is Lauren Hicks and on this podcast I share five minute episodes to help you grow in your faith. This podcast is about discipleship and spiritual growth. It's my prayer that these short episodes inspire you and encourage you to be a fully devoted follower of Jesus Christ.	\N	5	29	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:19.469325+00	\N
9ed54caf-a59d-4c92-97cc-cce813657c2d	d2127ddc-5a10-420e-b754-2dfa51975b3a	1	Opinion	If you're new to the podcast, let me invite you to subscribe on your favorite podcast app, so that you can join us each day. Today on the podcast we are talking about when God interrupts your plans. Recently, God interrupted my plans. Has this ever happened to you? I had made plans and to me, they seemed like really good plans. But then suddenly and without warning, God closed a door before me. It was completely unexpected. I'm not sure what God is going to do in this situation, but it is clear to me that he has interrupted my plans. You see, my life is filled with interruptions, inconveniences, frustrations and unexpected events.	\N	29	77	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:19.469325+00	\N
00841ccf-9eda-4b03-ad0a-74fe6efe9d08	d2127ddc-5a10-420e-b754-2dfa51975b3a	2	Language	Sometimes things break, accidents happen. The phone will ring just as I climb into bed. Traffic sometimes makes me late and just when I don't need another added expense and appliance will break. Unexpected illnesses change my carefully crafted plans. I could go on and on and you probably could too. My problem is that I often handle these interruptions poorly. I get frustrated, I complain, sometimes I get upset. Though these interruptions are unexpected and catch me off guard, they do not catch God off guard.	\N	78	113	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:19.469325+00	\N
92079ca8-1375-4cfc-a01a-a51d015ab002	d2127ddc-5a10-420e-b754-2dfa51975b3a	3	History	They are not random, meaningless events. In fact, these interruptions are divinely placed in my path for a reason. God will use these interruptions to change me to be more like Christ. An interruption can be God's tool to help us become more patient, more loving and more understanding. It can be God's way of guiding our steps and pointing us in the right direction. Divine interruptions can be God's hand-a-protection in our lives when we are starting to move in the wrong direction. God's interruptions are always for a reason. You know, as you read the Gospels, you can't help but notice that Jesus himself was interrupted and just about every day. There was always someone reaching out to him for healing, deliverance, provision, or simply a question. But then we see Jesus embracing the interruptions and serving those he came in contact with. For Jesus, the interruptions did not stop his ministry, the interruptions became his ministry.	\N	114	174	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:19.469325+00	\N
5045115e-d882-4ce8-b223-6eb5052456ea	d2127ddc-5a10-420e-b754-2dfa51975b3a	4	Opinion	Divine interruptions remind us that our knowledge and perspective is very limited. We cannot see and know as much as God. So we surrendered to his plan, recognizing that we serve a God who has all knowledge and he knows what is best for us. So if interruptions are God's plan for us, we must embrace them. Proverbs chapter 19 verse 21 says, many are the plans in a man's heart, but it is the Lord's purpose that prevails.	\N	175	203	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:19.469325+00	\N
88b0395b-ea76-4bbb-a9fd-b115032aa393	d2127ddc-5a10-420e-b754-2dfa51975b3a	5	Opinion	And I like Proverbs chapter 16 verse 9 which says, the heart of man plans his way, but the Lord establishes his steps. So what do we do when we are interrupted and we sense that God is at work in the interruption? First let me encourage you to pause and take a breath. It's so easy to become irritated and reactive when we face the frustration of an interruption. Second, pray and ask God to help you be aware of what you need to see. Ask the Lord to open your eyes to his direction.	\N	204	235	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:19.469325+00	\N
0d7642c8-eb70-4b87-b836-f4937b7b1d2b	d2127ddc-5a10-420e-b754-2dfa51975b3a	6	Opinion	Because of the interruption, there may be no clear path forward. In these instances, we have the opportunity to wait upon God and seek his direction. Remember, waiting on God is never wasted time. Third, be alert to the possibility of discouragement. When our plans don't work out when the door is shut in front of us and when we cannot move forward, it's so easy to become disappointed.	\N	236	260	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:19.469325+00	\N
7332110b-0ccc-43f9-bc1f-34e4c921d4ac	d2127ddc-5a10-420e-b754-2dfa51975b3a	7	Interview	Becoming discouraged is a choice. Don't give into it. Praise God anyway. Trust God is working in the interruption and that a testimony is coming soon. It has been said that a man's greatness is measured not by his talent or his wealth, but by what it takes to discourage him. So choose not to be discouraged. And remember this great truth from Romans chapter 8 verse 28, where the Apostle Paul wrote, and we know that for those who love God, all things work together for good, for those who are called, according to his purpose. And here's today's challenge. Have you been interrupted lately? Has God close the door that you were prepared to walk through? Trust that it is no accident. God has promised to direct your steps and his plans are always best. Hey, thanks again for joining me for today's episode. I hope you have a wonderful day. And until next time, let's continue on our journey as followers of Jesus.	\N	262	321	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:19.469325+00	\N
0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	bafdf69c-2cef-41b2-a740-fa9a646655f8	0	Opinion	Yo yo Yo, I hope this message finds you well However you found it however landed across your screen if you're listening I definitely appreciate it Sometimes it's all we need just listen in there, you know For my my name is me a lot M.E. L.E. to sometimes I go about a guy to meet a guy I'm see At the time some your brother you love All the above you know Love one and that's what I intend to do, you know, spread some love to you You know, hopefully it comes back to me, but	\N	7	56	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
23075003-e37a-4b81-ad14-4e57c96ced61	bafdf69c-2cef-41b2-a740-fa9a646655f8	1	Language	Even if it doesn't you know the love was free Yeah, I'll be trying to wrap, but you know me and definitely want to just come in today. It's just a little I don't even have anything to offer for M.E. But because of my testimony If I'm honest with you all, you know It's been a while since I've officially like talked about something and been Present if I'm honest, you know, I'm saying like the last year of my life has been the most	\N	56	87	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
d306ff91-3f61-4821-b0f3-4f0ee8ced382	bafdf69c-2cef-41b2-a740-fa9a646655f8	2	Inflation	Up and down year of my life never if I'm honest, but that's just thus far She like that, but right now I'm in a position in reminiscent of like 2020 bro Like it feels exactly like I'm in the exact same space as I was at that point You know at that point I was just got laid off of a job and	\N	87	107	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
05562109-70d0-47ae-8398-094a122b83d8	bafdf69c-2cef-41b2-a740-fa9a646655f8	3	Labor	Yeah, it was pandemic bro. I wanted to create. I wanted to do video and stuff like that And I started doing it and you know real life happens reality kicks in where it's like all right Yeah, you can make a video to get seen by like 2025 people Get your ass to work So that's what I did. I went to work. You know saying I started working at the ABC store to look a store Shout out to anybody at frequency there and you know for all the spirit Needs and shit like that. Yeah, shortly after you know saying I was doing a morning show and all that I do and everything all together It burnt myself out But like the beginning of 2021 and at that point, you know, it was like all right. I was tired of Working at the ABC store because it was like fam. You know, yeah, I'm getting a little bit of money	\N	109	156	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
d297f086-1cec-4531-8885-e12cf9bbfd47	bafdf69c-2cef-41b2-a740-fa9a646655f8	4	Opinion	But it's not let me be able to do what I want to do and that was the content so I went over to I only said went over like a job at a platform for like a year before hit hit me up So I was like all right cool, you know since better money career path all that shit	\N	156	171	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
a38c3a4a-b753-4327-8d03-2911e3cf9d65	bafdf69c-2cef-41b2-a740-fa9a646655f8	5	History	Did that feel like a year some change and you know Yeah Back to where I started you know, I mean now out digging to that story little later just now that Sometimes the writing is on the wall and we choose the ignore it But yeah, that's all not the top before another day, but yeah, man in the missed the wall it is like this is then the lowest	\N	172	195	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
6d87af8b-a11c-43cb-9a1f-b5c60aa0800d	bafdf69c-2cef-41b2-a740-fa9a646655f8	6	Theater	I've been in a very long time when I say low I don't just mean emotionally and nothing like I mean just like being out of the way like just not being seen Not one to be on social media and I want to be heard from like to my friends If there's anybody that considers me a friend or anything like that and I gave you the quote shoulder over the last Two years you're in half whatever I said a lot of my play if I'm honest and me trying to be the communicator that I am now like I should have said something so I do apologize as a friend to all of my friends	\N	195	231	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
53cf9e31-3e2d-40da-8897-c9365f9cb0be	bafdf69c-2cef-41b2-a740-fa9a646655f8	7	Language	But also on that side of that you know saying like I said I was I vowed bro I vowed to myself to shut the fuck up forever Part of it had to be because I was disgruntled, you know with the process and life and frustrations and shit like that But another part of it was	\N	231	248	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
e28be72f-f6e0-489b-b6d9-ee7c8d45e244	bafdf69c-2cef-41b2-a740-fa9a646655f8	8	Opinion	Me not believing in myself me not believing in my own dreams and shit like that and It's tough. This is this is what I will say it's tough when the people around you See the potential and you more than you see it in yourself or they see the greatness more than you'll see it in yourself	\N	249	269	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
bd3427cc-5db6-4715-a282-830c1e0a459a	bafdf69c-2cef-41b2-a740-fa9a646655f8	9	Careers	And it's tough to even try to muster up the courage to Try to go after that because for me man for a long time like I said Especially after taking on that career job and it lasted longer than I expected it to and I stopped for	\N	269	285	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
d45a38fa-d421-4737-91cb-a891b1cf555e	bafdf69c-2cef-41b2-a740-fa9a646655f8	10	Opinion	Coording and things like that like I honestly thought that was my life at the point I thought I was going to You know I thought I gave up when the dream and I even thought I gave up when the dream I I've given up on the dream a few times so for me to even be back here right now Boy it took a lot But I say that to say this I Was the video today about where we are in our lives and Oftentimes what we do we all the times are in a place in our lives where Two years ago six months ago two days ago we prayed to be in this position now that we're in this position We want to be in a better position. We want to be in a position of more what we're not taking a chance to truly appreciate How far we've came in Things we've been doing because for myself if I look back that is my one thing I'm proud of	\N	285	340	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
9cbdab12-261f-4b43-895a-ec80dacf5673	cdd24f31-01e3-4c08-b42d-d43151c6a877	4	Opinion	listened to your podcast on interior design. Why, why hasn't there been crossover? And he's like, I don't know. He's like, I would have thought the number was bigger. We had 100,000 people tune in. Again, not my followers. I was, I was brand new. I was nine weeks in. But it was because I was bringing people together. I feel like the sometimes and a lot of the	\N	139	162	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:42.995277+00	\N
6ba8ad2e-5dfc-46d5-b412-17ddf942000c	bafdf69c-2cef-41b2-a740-fa9a646655f8	11	Opinion	I'm not the same person I was At 25 not the same person I was at 26 and not the same person I was even when I turned 27 if you months ago like I've done a lot of growing Some of it oh my own some of it. I was forced to do You know For me My whole thing is just about being honest Like I know what I want out of this life Am I gonna get it that is the goal? I would love to get it But you know When they meet and draw love as our actions and how we choose the response So right now in my life In my space where I'm choose a happiness I'm choosing peace So I will say this if it doesn't work out Not that I tried and not that I was real all of it Really happened and I hope you do the same for yourself that I hope you show up for yourself Hope you give yourself the grace and love that you so desperately yearn for And I hope that you are friend to yourself today. I'm not sure exactly Where we end up? Where we go from here but I do know And the end Love is going when so with that I hope you take something And I appreciate you for listening Thank you	\N	340	469	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:25.865493+00	\N
53058727-0b38-4252-a713-7e62dd9097ec	607a6180-43d6-476f-847d-14a4d5c189e6	0	Opinion	Yeah, yeah, yeah, yeah, good morning good morning good morning. How about everybody out there's having a wonderful start to their day And if you just seen this on the preview what I thought would up though you know, I mean I ain't seen you on a minute I don't know what that was, but you know There we go. I've heard so you film me. It has been a while and I appreciate you guys for stopping But you know Welcome back to the five minute morning show with your host the guy that got in me the God MC's young Let appreciate you all for checking and you know what is this this probably like I got third time talking this year	\N	7	36	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:29.53171+00	\N
06063f5e-3182-4c0f-8f43-a79975c88ab7	607a6180-43d6-476f-847d-14a4d5c189e6	1	Opinion	You know, I hope you guys are having a wonderful year, and if not, you know, we got some time to make it Where for a while you film me, but today I definitely want to just come in and you know offer a little bit of perspective on a year into the pandemic and you know talk about what's to come next Honestly So with that be episode of playing instrument on eighth my flow today's instrument was provided by the great Erica Bob do with on and on two reasons that chose this instrument The first one is because you know it's a light instrument or something that I could walk to you film me is not a light going No, I could talk my talk we can do I think so the second reason is because I felt like this song is all about	\N	36	74	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:29.53171+00	\N
559eedd6-e8cd-4d7e-bc6d-c6eaeea9ccf6	607a6180-43d6-476f-847d-14a4d5c189e6	2	Opinion	Percivering honestly you know I mean regardless was going on in the north my side for keep going like a rolling star So we don't keep on pushing for me and that's all that we've actually been doing Since this pandemic has started so you know, I mean being a year into the pandemic The pandemic has changed a lot for us, you know, I mean almost every aspect of our lives has changed in some form of fashion	\N	74	97	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:29.53171+00	\N
8770672f-41f8-40d9-bcc2-028cba228ec5	607a6180-43d6-476f-847d-14a4d5c189e6	3	Opinion	You know, whether it was the routine that you normally do hitting the gym late night hit Man, they brought me a Walmart trips at the midnight But that's a whole not the story. You film me a lot of us lost loved ones a lot of us lost our jobs or had the lose hours lose just we lost a lot through the process But we also gained a lot through that time, you know And I could speak for myself on this one, you know, I mean I gained a lot of perspective along the way Just about where I was going and where I was trying to do especially with the unfoundist up for the whole Branding and things like that and you know, it gave me a lot of perspective It gave me a chance to actually understand why I moved the way I moved in what I'm actually trying to do deep down the side	\N	97	141	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:29.53171+00	\N
ae914bb1-1947-4980-8ca8-4247d9235231	607a6180-43d6-476f-847d-14a4d5c189e6	4	Arts	Yeah, yeah, man a lot of us you know Not that you just make it about me a lot of I'm proud of a lot of people, you know, I'm saying like I seen a lot of People step outside of their comfort zone during this day Some friends become became painters some people became traders	\N	143	159	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:29.53171+00	\N
178a8b9b-143d-4b06-a58f-31378d69d80d	607a6180-43d6-476f-847d-14a4d5c189e6	5	Family	Some people got closer to parents some people got closer to just people in general But deep down inside what I've realized throughout this entire thing was a lot of us are yearning for connection. That's why we're so heavy on social media. That's why It hurt moments outside got close, you know, I said because this was all we had to connect with each other Whether whether whether it was going to the club whether it was going to your favorite store Whatever it was you know, I'm saying it changed the fabric of things	\N	160	187	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:29.53171+00	\N
59b2068a-9fba-415f-83cb-3ed087819e4e	607a6180-43d6-476f-847d-14a4d5c189e6	6	Language	But that's leading me to the next point, you know, with the world about to open back up They calling for it by July 4th. They won everything to be back to them. Hey, that's cool That means we get a summer, but I do want to save this, you know regardless Yeah, regardless of what goes on this summer	\N	187	205	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:29.53171+00	\N
93945f60-21e9-44c7-8eb4-82c54e960ee6	607a6180-43d6-476f-847d-14a4d5c189e6	7	Opinion	I want everybody to actually enjoy themselves and take it all in, you know, I mean like We seen a year ago, you know, we didn't know exactly what was going on and we do know that this next time You know, it's about to be a little lit out here, you know, but enjoy yourselves be safe and As always, man, I appreciate you Like Honestly, I just I just lost all a change of thought, but I do have something I do want to save before I go Instead of giving you guys quotes. I mean, just be awesome game that I picked up alone in the way and I've been picking up a lot of game alone in the way So just be awesome that picked up last night Here we go The only time success comes before it work is in the dictionary So let's get to work you film me and You know me, I appreciate your efforts. I've been by now. I wanted to hear my voice see my face. I look good things like that and Be smooth. This was the guy. This was what for 30. Peace. I see you out the next time	\N	205	269	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:29.53171+00	\N
3a3c6b5c-1718-4eab-8d89-93bf5cd73b98	129a1e43-036a-4a0f-a99d-f4cb29a8eac6	0	Opinion	Yo Yo, it's been a minute, but we back up Benny you know I mean appreciate y'all for stopping by you For me welcome back to the five minute morning show with your host the guy the guy in me the guy MC Shung my luck. You know, hey, just want to start off by saying happy new year	\N	3	21	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:32.774999+00	\N
4f482f02-e3dd-4b98-9853-f5b1ab0ad8f5	129a1e43-036a-4a0f-a99d-f4cb29a8eac6	1	Opinion	No, it's been a minute since I've seen you guys, but you know Just want to come and tell you guys where I've been in it's all for a little bit of perspective I'm gonna need your entire file today and Let's hop right into you know, I mean with every episode. I play an instrument on to meet my flows today's instrument to	\N	22	38	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:32.774999+00	\N
dd46dff0-f1c4-4d04-95ad-c72af8d0895e	cdd24f31-01e3-4c08-b42d-d43151c6a877	5	Television	times like Joe Rogan, he brings all these people because, you know, like, people tune in and see who he's got next. I caught the Jimmy Fallon effect, too. Jimmy Fallon, I don't even know what he does, you know, during the day. I think he's like a schoolteacher. He just lives on set. I don't know, because you never hear from him the rest of the time. But he seems to know where everybody. And you	\N	162	183	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:42.995277+00	\N
5eaff0ce-cf4a-45f0-bd0b-17109af5def3	129a1e43-036a-4a0f-a99d-f4cb29a8eac6	2	Family	We've provided by JD kids with all for the love You know the reason I chose this instrument was because it's a classic, you know, and The reason is because we're doing this all for the love Yeah, just hop right into it. I guess you know me where I've been I've just been on a journey with myself Just trying to figure out where I'm going the direction that I want to go into and And actually just trying to figure out who I want to be and things like that So, you know, you just need to take some time myself off of myself the perspective give myself a chance to actually breathe and actually	\N	38	70	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:32.774999+00	\N
ff11d509-6549-4a1d-b3e3-f3f22e9f35b5	129a1e43-036a-4a0f-a99d-f4cb29a8eac6	3	Opinion	Get the answers, you know instead of trying to rush through things So that's what I've been doing, you know, I'm still on that journey So you guys might not hear from me as often or like the last little break you might not hear from me at all So that's that, but I definitely wanted to come in here today and offer this piece because Somebody might need to hear it and that is just the trusty self, you know You have your best interest at heart and sometimes we don't make the best decisions and things like that But you know, there's something to gain from actually the power of making your own decisions and the power of	\N	71	108	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:32.774999+00	\N
def7bf6f-1f86-4a7d-b314-1aa8f09798ee	129a1e43-036a-4a0f-a99d-f4cb29a8eac6	4	Language	choosing to live in your own life and That's where I've been at you know trust them myself learning how to trust myself and it all starts with You know being aware of who you are being honest with yourself and actually putting in the work So, you know, I'm not going to need you in time today like I said all I wanted to come in today and say	\N	108	131	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:32.774999+00	\N
d92b3fef-2f38-4ede-96ad-77deff28010c	129a1e43-036a-4a0f-a99d-f4cb29a8eac6	5	History	It's just trust yourself. Give yourself a chance to actually achieve what it is you say you want to do and you know All right, we can get there. I appreciate you guys as always I mean, I see me. I'm trying to put some kind of air in my life. You feel me trying to feel good about myself I've already can't see my blue lights, but they throw you know God knows in the back, I got to you know I'm trying to tell you that I found it logo and we here so Appreciate your eyes always be smooth be happy enjoy your mouth because you know it's black history You know wake up It's the first time I appreciate your eyes be smooth	\N	131	170	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:32.774999+00	\N
74b3f23d-3edb-4102-be3c-094abcfe129b	c285efb7-ee21-4a17-a54a-db3d545f5ae4	0	Opinion	Hey, hey, everyone. Welcome back to another episode of the Michael podcast on podcasting. I am your host, expert authority, business coach and podcast expert, Christine Blasdale. And it's been a while. I apologize. It's been quite a while since I've posted a new episode, but I've been busy. I've been very busy and part of that is because I have just released. Oh, I took some time to write my brand new book called Podcast Dynamics, unlocking the secrets of profitable podcasting for beginners. And it has been a project of love. I've just poured my heart and soul into this book. Again, it is for beginners. And it is not just about the current situation with podcasting and how you can use a podcast to promote your business and use it as a marketing tool.	\N	12	63	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:36.167279+00	\N
7e1a0421-5613-4d3b-9edd-c3f24c63a221	c285efb7-ee21-4a17-a54a-db3d545f5ae4	1	Opinion	But it's also about the future of podcasting and incorporating everything from chatGPT, AI technology, all of the great AI tools that you can use. But also what the future looks like when we are thinking about podcasts and podcast, which is the video version. I believe it's going to be a lot more interactive. I believe that your audience, your subscribers are going to have more of an interactive role with you.	\N	63	91	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:36.167279+00	\N
dc9120ec-bf89-4697-ab55-07d48c6a74f4	c285efb7-ee21-4a17-a54a-db3d545f5ae4	2	Economy	And I'm just super excited about about the book. And so today's episode is going to be talking about podcast economics. And if you'd like to get your copy, you can get the paperback version or you can get the Kindle ebook version as well. On Amazon, it is out now. And both additions are available for you to purchase. And if you're interested, the paperback is 2495, US, and the Kindle is 299. The great thing about the Kindle version is that you can actually click on all those links that I have. I have links to different suggested microphones, different software that I use.	\N	91	130	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:36.167279+00	\N
86d31a83-6f1c-420d-a29b-f10be67a427a	c285efb7-ee21-4a17-a54a-db3d545f5ae4	3	Books	So it's really a wonderful way to get resources and to access those resources right away. So I'm going to just take a real quick gander through this book that I'm, again, I'm so excited about this. And I wanted you to be the first to know about it because, well, you're my beautiful audience.	\N	130	149	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:36.167279+00	\N
eb9db050-7226-4f62-b1f6-7b4c62b846ad	c285efb7-ee21-4a17-a54a-db3d545f5ae4	4	Opinion	And you need to know what I've been doing. So just in some of the table of contents, the different chapters. Yes, podcasting is still the new gold rush. And now is the time to get in. That's chapter one. The chapter two is the popularity of podcasts keep growing. And chapter three is how to promote your own business with a podcast. That's one of my favorite chapters because it's about how you can no matter what your industry is or what your business is, how you can use a podcast to promote your business.	\N	150	180	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:36.167279+00	\N
231cfd16-7cdc-41cc-b341-93e8701ae698	c285efb7-ee21-4a17-a54a-db3d545f5ae4	5	Analysis	It goes on. We've gone to how you can promote your business as a podcast guest. I've been on many podcasts shows myself. Yes, you can also be a guest on podcast shows. And I love helping my clients get booked on different programs, radio, talk shows, all that stuff. How you can establish your expert authority with a podcast. It's really important showcase your wisdom showcase your specialty your area of expertise. Let your podcast be your platform where you let other people know what it is that you do and how you can help them. You can use your podcast to meet notable authors creators and dream guests. I have met so many amazing people with my podcasts. I have two currently right now and I'm developing a third podcast.	\N	181	226	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:36.167279+00	\N
e0da7891-30cc-4e3e-a092-ff5167c47b71	c285efb7-ee21-4a17-a54a-db3d545f5ae4	6	Opinion	And once that gets launched, I will let you know. But this this book is just it's full of information. How you can use your podcast to help others. How you can create income from your podcasts. And then we jump into the future of podcasting. I also give you some hot tips on how to record in zoom for your video version of your podcast.	\N	226	249	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:36.167279+00	\N
102eb6c8-62a9-4b10-8090-c6ba859e0222	c285efb7-ee21-4a17-a54a-db3d545f5ae4	7	Review	Some sneaky little tips and tricks. It's all included in the book. And I would love to see your review. If you're able to grab a copy, make sure you post your review. But the book is now available at Amazon. Again, if you're interested, there's going to be a link in the show notes. You can just click on it and get either the Kindle version for two dollars and ninety nine cents. What a bargain. Or you can get the paper back. If you're someone who likes to flip the pages over and highlight stuff. You can get the paper back to 24.95. All right. Make sure you check out the show notes. And until next time, happy podcast.	\N	251	286	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:36.167279+00	\N
a4780505-3d89-4c67-aa99-fcee721c3ca1	e9e0b659-b3c5-4118-9a94-4053ec89b00c	0	Opinion	Welcome back to the micro podcast on podcasting. I am your host Christine Blasdale your expert authority And I'm also a podcast coach for you folks who want to create a podcast in your beginning your journey Today's very special because in this episode We're going to be speaking with Julie Hood who is the creator behind course creators HQ.com and she's gonna talk about the importance that if you have a podcast Why you want to create a course based on your expertise and promote it in your podcast? Let's listen to what she has to say you can you talk about the importance if someone has created a podcast about the importance of creating a course and	\N	11	55	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:39.58001+00	\N
5197e620-0ddc-4bb2-b927-622f0b44c043	e9e0b659-b3c5-4118-9a94-4053ec89b00c	1	Opinion	About how they can advertise that course in their own podcast Yes, yes Right, so I work with a lot of podcasters who have recognized that building up an audience to where they could get to normal advertising rates It's gonna take a while So instead to have a monetization to your podcast One of the things I really really love is to use a mini course or a course of your own So especially if you have a non-fiction podcast where you're in helping people teaching people instructing people on a certain topic If you can put together a mini course or smaller course and you can sell that then on your podcast	\N	56	106	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:39.58001+00	\N
3e766071-0090-4bd9-8eb4-3749cb159b97	e9e0b659-b3c5-4118-9a94-4053ec89b00c	2	Analysis	And it doesn't have to be complicated or super sailsy. It's just a short little thing Hey, by the way, I've got this mini course. I put together if you want to learn more and you want to know about it Here's the link I'll put it in the show notes. You can click over and if it comes a really good revenue source a four podcasters that is not a typical one that a lot of people do you but I I've been	\N	106	129	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:39.58001+00	\N
f685208e-0981-42da-9263-dfd2651e560c	e9e0b659-b3c5-4118-9a94-4053ec89b00c	3	Interview	thrilled with it because I use my podcast all of the time to help connect with my students I would suggest that people also if you have if it's a You know if it's a book if it's a if it's a physical book or a course that is an evergreen Right, so that if anybody's listening to it in February or January or wherever It doesn't matter but if you if you're able to create in zoom make a 30 to 40 second Recording in zoom with either and showing them you know You can get this book or you can get this course any kind of visuals that you can have and it can go	\N	129	169	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:39.58001+00	\N
aef28f78-8ce3-4a77-80a7-9704b78102a5	e9e0b659-b3c5-4118-9a94-4053ec89b00c	4	News	You can do that in editing you can actually put the visual of the course the artwork and things But if you're able to create that in zoom then you have the video version of it and the audio So that you can insert it in your podcast, but you can also put it on YouTube with the video version of your podcast I do that right now with just Announcing my strategy sessions the free strategy sessions But I think for products specific it would be very very smart to just put that in there and again	\N	169	201	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:39.58001+00	\N
24c90231-560d-4cce-a2be-b52473e9d5dd	e9e0b659-b3c5-4118-9a94-4053ec89b00c	5	Opinion	Don't make it like she was saying don't make it five minutes long You know make it like a commercial make it short short and sweet boom Right and Give yourself plenty of runway. I had a coach once it told me six to eight weeks out from a specific thing you should be starting to talk about it	\N	201	219	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:39.58001+00	\N
0a288c49-568a-4d95-87fb-d37316d0dd46	e9e0b659-b3c5-4118-9a94-4053ec89b00c	6	Opinion	And I remember my mouth kind of dropped because I would do maybe a couple episodes two three episodes and she's like Oh no People need to hear it over and over again. So six to eight weeks ahead so yeah and same thing for your email Blast out as well. You got to remind people and give them and don't do a countdown clock necessarily	\N	219	238	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:39.58001+00	\N
00cac318-a567-4bca-9412-4f1d31b5b26d	e9e0b659-b3c5-4118-9a94-4053ec89b00c	7	Opinion	You don't have to but you could say you got four days left you got you know 24 hours left those type of things People will Especially when they are they're reminded that they don't have much time left They will you know hopefully respond and and get on there Julie hood you are amazing absolutely I'm so happy that you joined us today Once again that was Julie hood you could find out more information by going to course creators hq.com And since this episode is all about using your podcast to promote your courses your books I wanted to let you know that I have just released on Amazon the Kindle and the paperback version of Podcasting for beginners the workbook It is brand spanking new you can get yours on Amazon. I'll put the link in the show notes But check it out. I know you're going to love it. So check it out on Amazon and that's all we have time for today on the micro podcast on podcasting. Make sure you like subscribe comment as much as you can on this program And if you want to find out more about my coaching my podcast coaching you can go to Christine Blastale.com. That's Christine Blastale.com and until next time happy podcasting	\N	238	305	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:39.58001+00	\N
0ff77a0c-bcf4-4dd6-bb10-1a65b21eabab	cdd24f31-01e3-4c08-b42d-d43151c6a877	0	Opinion	Welcome back to the five minute micro podcast on podcasting. I'm your host Christine Blasdale and I'm excited for today's episode because I am a very special guest Mr. Joseph Hecker who is an amazing consultant for businesses. He's also a podcaster and he's going to be talking about the importance of being a guest on other podcast if you are a podcaster yourself	\N	12	34	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:42.995277+00	\N
b3e81349-ba49-483d-a50b-b8c9daa8f8a4	cdd24f31-01e3-4c08-b42d-d43151c6a877	1	Television	This is important. Catch our interview that we did just the other day. I think you're going to dig it and stay too think about also doing joint ventures. Join up with someone who you can compliment. One superhero is great. You know Batman alone is awesome. Superman. Yeah, cool. But when you have the, you know, the marvel, the team that can come in together, the audience gets something so different than just	\N	34	70	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:42.995277+00	\N
6cfb111d-e31d-4e12-91e0-1034938ab22e	cdd24f31-01e3-4c08-b42d-d43151c6a877	2	Arts	you alone. That's right. So that's what I recommend. And I think these co ventures that are happening. I'm doing a lot now. I'm doing workshops and things. And I love it because I can give my genius. But there's other people that have their genius. And when you put those two together, ooh, you create something so magical. Oh my gosh. I could touch you forever. Oh, yes, we do.	\N	70	93	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:42.995277+00	\N
1250558d-015d-4186-9b79-62560bbb3b88	cdd24f31-01e3-4c08-b42d-d43151c6a877	3	Analysis	And feeling like we're like, we compete or we stand our lane. And I won't see, I won't say the person's name. So when I hand those top design podcasts on, one of the people invited called me up beforehand and said, hey, so why would I do that? Like, you know, why would I, why would it be on a podcast with other podcasts and, and I said, oh, well, here. So Louanne was going to be on the podcast. I was like, hey, we're pull up her Facebook. How many mutual friends do you guys have? And so he looked and he was like, oh man, I only have 98. And I was like, okay, but her followers listened to her podcast on interior design. Your followers	\N	93	139	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:42.995277+00	\N
a85fcee4-204c-4853-9e0e-71962d2b717d	cdd24f31-01e3-4c08-b42d-d43151c6a877	6	Opinion	don't really tune in for Jimmy. You tune in for his guest. Lean into the guest part of it. It will help your numbers grow. Lean into that your, you've got people here locally like the guy Curtis Engels who was the crap or king. You know, he's, he is somebody in the port of the body business. And obviously, people looked up to him and said, hey, if Ed's doing it or if Curtis is doing that, then I'm going to sign up here, too. You know, so you never know. You never know. But it is worth something. I love it. Oh my gosh. I can talk to you forever. And you are welcome back any time because I, I like that you think outside.	\N	183	230	2ac4d568-938e-4ee5-8a87-f3e8827487e3	2026-06-09 14:19:42.995277+00	\N
\.


--
-- Data for Name: embeddings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.embeddings (id, chapter_id, episode_id, podcast_id, level, embedding, batch_id, processing_updated_at) FROM stdin;
\.


--
-- Data for Name: episodes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.episodes (id, podcast_id, guid, title, published_at, duration_seconds, audio_key, xml_key, transcript_key, cover_key, ingested_at, source_system_updated_at, processing_updated_at, preprocessing_updated_at, ingestion_updated_at, enclosure_url, summary, batch_id) FROM stdin;
965ae3a7-97e3-4354-81ab-91cbe0b0e3ae	cc9e1bba-01a8-49b8-9b08-931fcb751fbf	7a101868-6074-11f1-ac3a-9b7e5f66f598	Start With One Truth This Week	2026-06-08 07:05:00+00	372	cc9e1bba-01a8-49b8-9b08-931fcb751fbf/7a101868-6074-11f1-ac3a-9b7e5f66f598/audio/original.mp3	\N	cc9e1bba-01a8-49b8-9b08-931fcb751fbf/7a101868-6074-11f1-ac3a-9b7e5f66f598/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:18:58.743378+00	2026-06-09 14:16:49.483967+00	https://pdst.fm/e/swap.fm/track/JhoQDAATtO1l0y8tdKNa/pscrb.fm/rss/p/traffic.megaphone.fm/ACCCI9878540722.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
c1492e6f-9fed-415c-b0ad-306ec03030b8	cc9e1bba-01a8-49b8-9b08-931fcb751fbf	cc7c89c6-5b31-11f1-a892-4f5be40352c9	The Courage To Create Without Approval	2026-06-05 07:05:00+00	269	cc9e1bba-01a8-49b8-9b08-931fcb751fbf/cc7c89c6-5b31-11f1-a892-4f5be40352c9/audio/original.mp3	\N	cc9e1bba-01a8-49b8-9b08-931fcb751fbf/cc7c89c6-5b31-11f1-a892-4f5be40352c9/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:04.179359+00	2026-06-09 14:16:49.483967+00	https://pdst.fm/e/swap.fm/track/JhoQDAATtO1l0y8tdKNa/pscrb.fm/rss/p/traffic.megaphone.fm/ACCCI1702256825.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
3b4e2a60-3d08-4d47-9aff-751d2125d95b	cc9e1bba-01a8-49b8-9b08-931fcb751fbf	bbb0a47e-5b31-11f1-b98d-37ac693eef8d	You Can Still Change	2026-06-03 07:05:00+00	245	cc9e1bba-01a8-49b8-9b08-931fcb751fbf/bbb0a47e-5b31-11f1-b98d-37ac693eef8d/audio/original.mp3	\N	cc9e1bba-01a8-49b8-9b08-931fcb751fbf/bbb0a47e-5b31-11f1-b98d-37ac693eef8d/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:07.589032+00	2026-06-09 14:16:49.483967+00	https://pdst.fm/e/swap.fm/track/JhoQDAATtO1l0y8tdKNa/pscrb.fm/rss/p/traffic.megaphone.fm/ACCCI6828879513.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
ed61d48f-1a11-4d2b-988c-da9d203496fa	a61a6592-62c4-46ce-adc0-d486e81614ea	Buzzsprout-19274558	#1,516: God Promises His Presence	2026-06-09 08:00:00+00	321	a61a6592-62c4-46ce-adc0-d486e81614ea/Buzzsprout-19274558/audio/original.mp3	\N	a61a6592-62c4-46ce-adc0-d486e81614ea/Buzzsprout-19274558/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:10.932263+00	2026-06-09 14:16:49.483967+00	https://www.buzzsprout.com/1032730/episodes/19274558-1-516-god-promises-his-presence.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
0e3e6c19-5048-46e8-a206-1b51865c0f62	a61a6592-62c4-46ce-adc0-d486e81614ea	Buzzsprout-19274502	#1,515: You Can Be an Encourager	2026-06-08 08:00:00+00	317	a61a6592-62c4-46ce-adc0-d486e81614ea/Buzzsprout-19274502/audio/original.mp3	\N	a61a6592-62c4-46ce-adc0-d486e81614ea/Buzzsprout-19274502/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:15.005714+00	2026-06-09 14:16:49.483967+00	https://www.buzzsprout.com/1032730/episodes/19274502-1-515-you-can-be-an-encourager.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
d2127ddc-5a10-420e-b754-2dfa51975b3a	a61a6592-62c4-46ce-adc0-d486e81614ea	Buzzsprout-19274465	#1,514: God's Interruptions	2026-06-05 08:00:00+00	339	a61a6592-62c4-46ce-adc0-d486e81614ea/Buzzsprout-19274465/audio/original.mp3	\N	a61a6592-62c4-46ce-adc0-d486e81614ea/Buzzsprout-19274465/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:19.478359+00	2026-06-09 14:16:49.483967+00	https://www.buzzsprout.com/1032730/episodes/19274465-1-514-god-s-interruptions.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
bafdf69c-2cef-41b2-a740-fa9a646655f8	3d8d2033-4296-468c-96d9-3ae11750a12e	ebe117e4-ce63-437f-b519-63412569d4da	A Testimony For You	2022-10-24 18:32:17+00	472	3d8d2033-4296-468c-96d9-3ae11750a12e/ebe117e4-ce63-437f-b519-63412569d4da/audio/original.mp3	\N	3d8d2033-4296-468c-96d9-3ae11750a12e/ebe117e4-ce63-437f-b519-63412569d4da/audio/transcript.json	3d8d2033-4296-468c-96d9-3ae11750a12e/ebe117e4-ce63-437f-b519-63412569d4da/cover/image.jpg	2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:25.874723+00	2026-06-09 14:16:49.483967+00	https://media.transistor.fm/70551e09/8eaecf7e.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
607a6180-43d6-476f-847d-14a4d5c189e6	3d8d2033-4296-468c-96d9-3ae11750a12e	895df1c9-2e58-4154-b453-54e3db753845	5 Minute Morning Show EP. 44	2021-03-16 12:00:00+00	270	3d8d2033-4296-468c-96d9-3ae11750a12e/895df1c9-2e58-4154-b453-54e3db753845/audio/original.mp3	\N	3d8d2033-4296-468c-96d9-3ae11750a12e/895df1c9-2e58-4154-b453-54e3db753845/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:29.538457+00	2026-06-09 14:16:49.483967+00	https://media.transistor.fm/58ae13c0/90118b07.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
129a1e43-036a-4a0f-a99d-f4cb29a8eac6	3d8d2033-4296-468c-96d9-3ae11750a12e	71ee5482-0424-4365-b8bc-e816009c4a8f	5 Minute Morning Show EP. 43	2021-02-01 13:00:00+00	170	3d8d2033-4296-468c-96d9-3ae11750a12e/71ee5482-0424-4365-b8bc-e816009c4a8f/audio/original.mp3	\N	3d8d2033-4296-468c-96d9-3ae11750a12e/71ee5482-0424-4365-b8bc-e816009c4a8f/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:32.780692+00	2026-06-09 14:16:49.483967+00	https://media.transistor.fm/3900df72/53670417.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
c285efb7-ee21-4a17-a54a-db3d545f5ae4	6af8bbee-b82d-425e-99a5-ff5fd18b61ef	themicropodcast.podbean.com/3a2349c7-7b51-395b-b18e-d52ca0aaa752	Episode 46: Podcastonomics Is Now Available On Amazon!	2023-09-30 01:23:40+00	293	6af8bbee-b82d-425e-99a5-ff5fd18b61ef/themicropodcast.podbean.com/3a2349c7-7b51-395b-b18e-d52ca0aaa752/audio/original.mp3	\N	6af8bbee-b82d-425e-99a5-ff5fd18b61ef/themicropodcast.podbean.com/3a2349c7-7b51-395b-b18e-d52ca0aaa752/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:36.178488+00	2026-06-09 14:16:49.483967+00	https://mcdn.podbean.com/mf/web/h4ckvr/episode_46_AUDIOa7ymx.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
e9e0b659-b3c5-4118-9a94-4053ec89b00c	6af8bbee-b82d-425e-99a5-ff5fd18b61ef	themicropodcast.podbean.com/4c2b7bb6-b4ed-30ed-93f4-1260b94307a1	Episode 45: How To Promote Your Courses and Books On Your Podcast	2023-06-21 02:17:51+00	310	6af8bbee-b82d-425e-99a5-ff5fd18b61ef/themicropodcast.podbean.com/4c2b7bb6-b4ed-30ed-93f4-1260b94307a1/audio/original.mp3	\N	6af8bbee-b82d-425e-99a5-ff5fd18b61ef/themicropodcast.podbean.com/4c2b7bb6-b4ed-30ed-93f4-1260b94307a1/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:39.586706+00	2026-06-09 14:16:49.483967+00	https://mcdn.podbean.com/mf/web/3iugb3/episode45_promote_your_course_and_books_AUDIO9wy6x.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
cdd24f31-01e3-4c08-b42d-d43151c6a877	6af8bbee-b82d-425e-99a5-ff5fd18b61ef	themicropodcast.podbean.com/f2181555-606b-3b5f-982d-9cca69d0c859	Episode 44: Why Podcasters Need to Be A Guest on Podcasts!	2023-05-15 04:51:13+00	241	6af8bbee-b82d-425e-99a5-ff5fd18b61ef/themicropodcast.podbean.com/f2181555-606b-3b5f-982d-9cca69d0c859/audio/original.mp3	\N	6af8bbee-b82d-425e-99a5-ff5fd18b61ef/themicropodcast.podbean.com/f2181555-606b-3b5f-982d-9cca69d0c859/audio/transcript.json		2026-06-09 14:16:49.483967+00	2026-06-09 14:16:49.483967+00	\N	2026-06-09 14:19:43.000569+00	2026-06-09 14:16:49.483967+00	https://mcdn.podbean.com/mf/web/gwazqf/episode44_why_guest_on_podcasts_audio6x3qq.mp3	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3
\.


--
-- Data for Name: fact_checked_claims; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.fact_checked_claims (id, chapter_id, claim_idx, claim, verdict, explanation, sources, batch_id, processing_updated_at) FROM stdin;
\.


--
-- Data for Name: pipeline_batches; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pipeline_batches (id, stage, load_mode, status, start_ts, fin_ts) FROM stdin;
001d9b27-f688-43fc-a4f4-a871044ff731	ingestion	full	consumed	2026-06-09 14:16:06.0963+00	2026-06-09 14:16:49.486071+00
f6f9cbc2-1f6e-4176-bddc-6ddaf5745f2e	transcription	full	consumed	2026-06-09 14:16:49.52225+00	2026-06-09 14:18:50.791646+00
2ac4d568-938e-4ee5-8a87-f3e8827487e3	segmenting	full	success	2026-06-09 14:18:50.981012+00	2026-06-09 14:19:43.006337+00
\.


--
-- Data for Name: podcasts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.podcasts (id, guid, hosts, feed_url, title, description, episode_count, categories, image_url, ingested_at, published_at, batch_id, source_system_updated_at, processing_updated_at, preprocessing_updated_at, ingestion_updated_at, max_episodes) FROM stdin;
d1dd85b9-3bda-4301-b21f-ac73acca0bb3	Forrest KellyThe Best 5 Minute Wine Podcast	Forrest Kelly	https://feeds.captivate.fm/thebest5minutewine/	The Best 5 Minute Wine Podcast	The Best 5 Minute Wine Podcast is a weekly podcast by Forrest Kelly exploring wineries around the world. We take 5 minutes and give you wine conversation starters and travel destinations. In addition, you'll hear candid interviews from those shaping the wine field. Join us as we become inspired by their search for extraordinary wine and wineries.\n\nVoted One of The Best Travel Podcasts and Top 5 Minute Podcasts.	195	{Arts,Food,"Society & Culture","Places & Travel",Leisure,Hobbies}	https://artwork.captivate.fm/3082765f-8e8b-4552-877a-8d7dbee5125f/3EN-QzyPizV-ur0HL8Gyeslz.png	2026-06-09 14:06:47.588943+00	\N	001d9b27-f688-43fc-a4f4-a871044ff731	2025-03-27 22:15:01+00	\N	\N	2026-06-09 14:16:14.485452+00	3
cc9e1bba-01a8-49b8-9b08-931fcb751fbf	Headspace StudiosRadio Headspace	Headspace Studios	https://feeds.megaphone.fm/ADL5417720568	Radio Headspace	Join us every weekday morning to take a few moments to step out of the internal chatter and external noise. We'll pause and reflect to consider what brings us together in this shared human condition and how we can live a life that best reflects our limitless potential.	1700	{"Health & Fitness","Mental Health"}	https://megaphone.imgix.net/podcasts/57dfcdb6-50a9-11ee-9054-833b5b28125e/image/84657ca904f37ca5d2034887fa239845.png?ixlib=rails-4.3.1&max-w=3000&max-h=3000&fit=crop&auto=format,compress	2026-06-09 14:06:46.118413+00	\N	001d9b27-f688-43fc-a4f4-a871044ff731	\N	\N	2026-06-09 14:19:07.590471+00	2026-06-09 14:16:06.849926+00	3
a61a6592-62c4-46ce-adc0-d486e81614ea	Loren HicksThe 5 Minute Discipleship Podcast	Loren Hicks	https://rss.buzzsprout.com/1032730.rss	The 5 Minute Discipleship Podcast	<p>Daily episodes are hosted by Pastor Loren Hicks. This podcast will challenge you to go deeper into your Christian faith. The goal is to inspire you to be a fully devoted follower of Jesus Christ. Episodes have been downloaded over 700,000 times.</p>	1547	{"Religion & Spirituality",Christianity}	https://storage.buzzsprout.com/5ajr97jgfc3phr8oav0yyoil6gwn?.jpg	2026-06-09 14:06:46.869983+00	\N	001d9b27-f688-43fc-a4f4-a871044ff731	2026-06-09 14:01:53+00	\N	2026-06-09 14:19:19.479359+00	2026-06-09 14:16:11.847938+00	3
3d8d2033-4296-468c-96d9-3ae11750a12e	GOD MC5 Minute Morning Show	GOD MC	https://feeds.transistor.fm/5-minute-morning-show	5 Minute Morning Show	Every weekday on the wake up, the God blesses the mic with some inspiration and perspective to help push the day forward. Tune in for a piece of positivity everyday.	45	{"Society & Culture"}	https://img.transistor.fm/cY6AQv6rhWj5yfE6gYWIQr2KHMpCJrYjIyM7z6uyQPw/rs:fill:0:0:1/w:1400/h:1400/q:60/mb:500000/aHR0cHM6Ly9pbWct/dXBsb2FkLXByb2R1/Y3Rpb24udHJhbnNp/c3Rvci5mbS9zaG93/LzE1OTAxLzE2MDQy/NTY1OTQtYXJ0d29y/ay5qcGc.jpg	2026-06-09 14:06:47.725496+00	2025-05-02 14:55:25+00	001d9b27-f688-43fc-a4f4-a871044ff731	2025-12-02 21:56:09+00	\N	2026-06-09 14:19:32.781799+00	2026-06-09 14:16:17.621603+00	3
6af8bbee-b82d-425e-99a5-ff5fd18b61ef	Christine BlosdaleThe 5 Minute Micro Podcast on Podcasting	Christine Blosdale	https://feed.podbean.com/themicropodcast/feed.xml	The 5 Minute Micro Podcast on Podcasting	For anyone who wants to create a podcast, “The 5 Minute Micro Podcast on Podcasting” is a valuable source of bite size tips, tricks and resources. Each episode gives listeners insights into podcast-related topics - and it’s all done in 5 minutes or less! Hosted by award winning broadcaster and podcast coach Christine Blosdale, this show can help you get to rockstar podcaster status in no time! Learn more at ChristineBlosdale.com	46	{"Education:How To",Education,"How To"}	https://pbcdn1.podbean.com/imglogo/image-logo/11416001/Untitled_design_9__qb3t3g.jpg	2026-06-09 14:06:47.839678+00	2023-09-30 01:23:40+00	001d9b27-f688-43fc-a4f4-a871044ff731	2023-09-30 01:23:40+00	\N	2026-06-09 14:19:43.001497+00	2026-06-09 14:16:20.029895+00	3
\.


--
-- Data for Name: transcript_lines; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.transcript_lines (id, chapter_id, line_idx, start_time, end_time, text, emotion, emotion_score, batch_id, processing_updated_at, preprocessing_updated_at) FROM stdin;
23964f4b-bb17-438a-975d-49f818f88106	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	0	0	3	Life doesn't always come with a pause button.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
662da88a-f0c0-42e8-b26a-36a58fb9740a	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	1	3	7	There's always something pulling your attention, someone asking for more.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
bf91bbe8-fe20-427d-a1a9-4226b9e0b45a	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	2	8	11	Most days you're just moving through, trying to keep up.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
10722315-7b08-49ce-ac47-5ead0e1fc594	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	3	12	16	As the to-do list gets longer, you don't always realize how much your mind is caring.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
ef1e4b04-b5dd-423d-b3c4-d5974af69811	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	4	17	20	It's easy to forget to check in without you really doing.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
f3a8acce-cc7b-4bb2-9ed0-daef6f0d1ac8	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	5	21	22	But headspace can help.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
8b8399e6-dd8a-4e31-97be-1683ceef9a4d	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	6	23	27	Now headspace works with your Apple Watch to support your mind when your body says you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
b90f2e4b-5c1e-4930-95a7-daca853d6d6b	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	7	27	28	need it.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
99299cb6-ebad-4481-bc73-2e0ba221323e	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	8	29	32	This mental health awareness month tap into what your mind needs.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
596672ce-7ad1-43da-a574-f9e395fd1033	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	9	33	38	Now that headspace works with Apple Watch, you can meditate on a walk, take a breath	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
d119d076-9f24-46a3-838f-9f07bcf6b444	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	10	38	43	during a meeting, or stay calm while sitting in traffic, all without using your phone	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
e6972daa-0220-4deb-8ba9-49fbbe1131cb	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	11	43	44	screen.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
79ba763f-4e40-4a91-be7f-083b67212668	f9cbfe5d-ef47-4411-88b7-1626bd5c821d	12	44	50	And throughout your day, headspace sends gentle nudges to your Apple Watch with quick breathing	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
cc9f1954-a579-43b2-9ff6-5e6dca7affc0	c5e25575-2b26-4922-b0e3-47f43e425c13	0	50	52	exercises to help you relax.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
063774c6-4510-4fdb-b4b2-0b4a7c2506a1	c5e25575-2b26-4922-b0e3-47f43e425c13	1	52	56	A breath at the right time can change your entire day.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
3f76dbe3-b594-4cdd-bbb6-f493822d61c3	c5e25575-2b26-4922-b0e3-47f43e425c13	2	56	60	Go to headspace.com to start your free trial today.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
6eeb8dee-c04f-41e5-a332-f149b9c86fdc	c5e25575-2b26-4922-b0e3-47f43e425c13	3	74	78	Hi, it's Andy here, and welcome to Radio Headspace, until the start of the week, Monday	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
994b21b5-6093-42bd-8c49-bf05580c09b6	c5e25575-2b26-4922-b0e3-47f43e425c13	4	78	79	morning.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
7fcecc02-3523-4c6d-ae2f-fdb3531cfe76	c5e25575-2b26-4922-b0e3-47f43e425c13	5	79	84	Now you may already have kids, you may not have them yet, but if you could teach your	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
9c6fe187-f6cb-4d06-a9eb-e16d932533d1	c5e25575-2b26-4922-b0e3-47f43e425c13	6	84	91	kids just one valuable lesson, the most valuable lesson that you think they would benefit	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
334c55b5-6045-4d30-a6f1-b6bb63b0ccee	c5e25575-2b26-4922-b0e3-47f43e425c13	7	91	93	from in their life, what would it be?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
fa75b8ae-a5e4-4ef1-b3c3-adae716c2451	20d73e1a-b024-416e-9710-69e30acf0a0a	0	94	99	You know, I have some friends who believe the most important thing is that their child	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
12966ed0-e605-4e58-ac2c-f7be2378ea1b	20d73e1a-b024-416e-9710-69e30acf0a0a	1	99	99	feels loved.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
3d99e2f1-3860-48b5-8495-514c802c9801	20d73e1a-b024-416e-9710-69e30acf0a0a	2	100	103	No matter what else happens, that's the most important thing, that's the most valuable	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
a7d78452-55d5-4fa7-ab8a-7dd84f16b3c3	20d73e1a-b024-416e-9710-69e30acf0a0a	3	103	103	lesson.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
a8d63d0f-1182-40ca-8a61-c37233f82744	20d73e1a-b024-416e-9710-69e30acf0a0a	4	103	107	Now have another friend who thinks it's honesty, he always says to his son, you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
7f959faf-b4ee-4514-a0ae-e025f44ea363	20d73e1a-b024-416e-9710-69e30acf0a0a	5	107	110	know, I don't care what you do as long as you tell me the truth.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
05747a78-dfa1-4b67-bcd0-ab0e899589d2	20d73e1a-b024-416e-9710-69e30acf0a0a	6	110	113	That is the most important thing in life.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
db28384d-6ea3-465b-b05b-e81ea4554257	20d73e1a-b024-416e-9710-69e30acf0a0a	7	115	119	And a friend asked me the other day, what would I teach my son or do I try to teach	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
c35f8022-b20b-45aa-8280-4d9ad82dd55e	7da0e586-1f05-4ed2-9592-37db3933a831	0	119	120	my son's?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
f913d9e0-a16d-4389-a252-c65814c0e743	7da0e586-1f05-4ed2-9592-37db3933a831	1	120	124	But when my son sits still for long enough to actually listen to me, you know, I will	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
acd7dd72-64ef-4c61-a118-63bc75e03408	7da0e586-1f05-4ed2-9592-37db3933a831	2	124	130	always come back to the four foundations that were taught to me at the beginning of the	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
0ae87ffd-fe70-44e6-a42a-b6fb06c49ed3	7da0e586-1f05-4ed2-9592-37db3933a831	3	130	130	monastery.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
cedcf439-7ec9-44a6-9ca7-90298d20d3bc	7da0e586-1f05-4ed2-9592-37db3933a831	4	131	134	I genuinely have found them the most useful things.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
7d66d9a5-34a9-48ea-94c9-fa559e89226c	7da0e586-1f05-4ed2-9592-37db3933a831	5	134	138	I've still find them useful to this day, and because they're not beliefs, because	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
023c828a-2402-42ec-bd1c-93a4df6d02fa	7da0e586-1f05-4ed2-9592-37db3933a831	6	138	142	they're just sort of fundamental truths in life, we can't really avoid them, we'll find	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
0872713b-e8e6-4541-9340-ac32bdfb18f5	b57fa5d6-7694-45b5-8914-f43d82105f7f	0	142	144	them in every part of our life.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
07782c99-1335-4ad7-8d0b-8bcd3bb09ab9	b57fa5d6-7694-45b5-8914-f43d82105f7f	1	145	149	And even when one doesn't connect or relate, you can always sort of lean on another	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
2aecd664-6fc7-4659-bf46-23bde4691bba	b57fa5d6-7694-45b5-8914-f43d82105f7f	2	149	150	of the four.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
0cb0ce8c-6187-426a-ac5a-d83315781e74	b57fa5d6-7694-45b5-8914-f43d82105f7f	3	150	153	So I'm cheating a little bit, it's not just one thing, it's four things.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
ad42440f-1cf0-428a-b145-715e8cf20773	b57fa5d6-7694-45b5-8914-f43d82105f7f	4	153	156	But I thought it's shared them with you.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
0c2e22a1-239b-43e2-9631-1b36e121683c	b57fa5d6-7694-45b5-8914-f43d82105f7f	5	156	162	The first one is this idea of a precious human life, the idea that, you know, we might	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
fcf9f735-9d34-4462-9591-2f604ead4a9c	b57fa5d6-7694-45b5-8914-f43d82105f7f	6	162	166	take life for granted, especially when things aren't going our way, when we're not enjoying	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
fe4ce847-2810-4a32-a613-a7c55b6536a5	b57fa5d6-7694-45b5-8914-f43d82105f7f	7	166	169	life perhaps, there is a sense of taking it for granted.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
9a1fcc92-c666-487e-93c9-c52e6c23bc0e	b57fa5d6-7694-45b5-8914-f43d82105f7f	8	169	172	We don't appreciate just how precious it is.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
bb29bd57-1242-4a3d-8b19-c4b3853def23	4dd363c8-39ef-453c-9beb-05c74366dba2	0	172	177	And it often takes perhaps the death of a loved one or a close friend or something that	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
d851e95f-7865-45be-bcfd-3746a47960c6	4dd363c8-39ef-453c-9beb-05c74366dba2	1	177	183	really, really shocks us to cut through that chatter in the mind, to get us to a point	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
57f6c36f-3f97-4f05-b086-2d194022afe0	d61399a3-e22c-465d-b45d-4ccf0c270667	1	195	196	for his life.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
9b34fec8-9a9f-4231-b2a5-5f4c1aa1f2e2	4dd363c8-39ef-453c-9beb-05c74366dba2	2	183	189	where we realise just how fortunate we are to be alive and to recognise those things	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
5fb3d9f5-4d06-4294-a790-8b4159b15850	4dd363c8-39ef-453c-9beb-05c74366dba2	3	189	191	that are going well.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
fb3d36d1-ba07-4d6d-9807-97ea99d5cd56	4dd363c8-39ef-453c-9beb-05c74366dba2	4	191	195	So that's the first one, I feel like that's just useful on any given day.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
74cc4362-1494-466e-afb3-3415aef6c134	4dd363c8-39ef-453c-9beb-05c74366dba2	5	196	199	The second one is the impermanence, the idea of change.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
91af8830-4dea-4c8a-bd1a-2bce7067c7ae	4dd363c8-39ef-453c-9beb-05c74366dba2	6	199	203	Most of our life we are sort of fighting change, I think.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
13121c2d-1d63-42ad-9c4e-efe27ba31cf6	4dd363c8-39ef-453c-9beb-05c74366dba2	7	203	207	Although we might have an idea that, oh, you know, with someone that enjoys change, and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
8a9fc10d-b656-4aa5-b1e8-4aa95441c2fb	4dd363c8-39ef-453c-9beb-05c74366dba2	8	207	213	we might thrive as a result of it, think fundamentally, we assume in beings we like	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
32096a9e-de72-4e45-85ef-f315790588cd	4dd363c8-39ef-453c-9beb-05c74366dba2	9	213	217	the idea of safety and security and comfort, change can feel almost sort of threatening	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
055c18ef-2a2f-4899-9ade-0f1c9c08172b	18b04d89-6ab0-43b2-b945-9d326e64a688	0	217	219	in some ways.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
7cdebb7e-0a0f-4b4d-89f1-d410b9a7fd38	18b04d89-6ab0-43b2-b945-9d326e64a688	1	219	223	And even in the mind, we might struggle with the idea that things are always changing.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
852dd798-546e-4f5c-b852-4c262847b46c	18b04d89-6ab0-43b2-b945-9d326e64a688	2	224	227	We might try to hold on to the things that we like and we might try and resist the things	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
5a85b755-0e2f-4d12-8d72-b555376ac45d	18b04d89-6ab0-43b2-b945-9d326e64a688	3	227	228	that we don't like.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
672660e2-df81-4026-b5b0-2a6ace76894f	18b04d89-6ab0-43b2-b945-9d326e64a688	4	229	235	But once we accept that change is all around us, internally and externally, there is nothing	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
d049c630-9c30-4746-b121-5f101d2b3c92	18b04d89-6ab0-43b2-b945-9d326e64a688	5	235	240	to hold on to and equally there is nothing to fear because everything is changing all	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
e615c9ed-d8d7-4691-b283-6552080d7d6e	18b04d89-6ab0-43b2-b945-9d326e64a688	6	240	241	of the time.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
e987b855-3077-439c-aa44-d900d7f8a8a3	18b04d89-6ab0-43b2-b945-9d326e64a688	7	242	247	The third one's cause and effect, although we know this intellectually, I think very often	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
02ddc803-6ce6-4bef-9079-15acf573d8e5	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	0	247	249	in life we don't live our lives this way.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
f6db588d-7b0c-4d5f-9ddd-ab54d8760c15	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	1	250	255	Everything that we do has some kind of impact and very often in life we will continue	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
a8c63db2-1f2e-49d3-9944-ae355b6250e7	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	2	255	261	to do the same things that lead to a somewhat negative outcome or say the same things	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
5f9acbc9-8768-4348-b2be-34683dd6689c	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	3	261	266	that lead to a negative outcome without really acknowledging the cause of that.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
1c6e8a70-cb7f-4010-a6b6-8e952d96c75d	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	4	266	271	But once we start to see that and recognize it, it makes no sense to do those things,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
fa497b9d-2bc5-4beb-a0dc-783800cf32e1	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	5	271	272	to repeat those things.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
a704d250-0316-4e1f-b469-f906fc5e8a43	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	6	272	277	So once we have enough awareness and clarity around those, we have the opportunity to	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
4d05c213-e160-47e0-9634-7c3f534438c5	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	7	277	279	choose a different course of action.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
acc32910-e1df-4d65-b19a-99008450cf48	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	8	279	284	Feel like that one's especially useful for kids who are still very much in the mode of	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
90a5461c-fdec-46bf-98a1-2178c978aede	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	9	284	288	discovering what leads to a good outcome and what leads to a less good outcome.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
16d6d70a-e53a-4278-931a-d54ebbd55e01	ddfc2e09-e96f-4f29-963a-d9d2c7380b71	10	289	293	The final one is a sense of acceptance and I don't mean acceptance in the sense of just	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
7fc0639d-b865-4a07-b73b-244024933b6e	ed3af611-6a74-44ce-baba-fbbf9391ff17	0	293	299	letting things be as they are, to some things need to change and it's good to have clarity	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
bf905a97-cfa8-4275-a5e8-975981edee6f	ed3af611-6a74-44ce-baba-fbbf9391ff17	1	299	301	around what needs to change.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
ac68c209-a477-4af3-8e2f-94ee63f26c19	ed3af611-6a74-44ce-baba-fbbf9391ff17	2	301	307	But there's also sort of a broader acceptance that in life, life is a mixture.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
3cf3b243-5c2c-4e18-af17-4d429b458976	ed3af611-6a74-44ce-baba-fbbf9391ff17	3	307	313	There's not just happiness, we may strive for eternal happiness for this idea that we	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
e6b5f693-8ad7-4cca-82ba-bf51cc7cd122	ed3af611-6a74-44ce-baba-fbbf9391ff17	4	313	318	will be happy all of the time if we can just work things out in a certain way.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
1bb1671b-529c-4323-b072-8b9f10813412	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	0	318	323	Life's way more complicated than that and if we can come to terms with the fact that sometimes	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
2c092da7-79cd-4832-b17a-1254419c122c	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	1	323	328	life is stressful, sometimes life is difficult, sometimes life is painful and that those	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
97c95eb8-e133-4958-a815-5e7fb622aba3	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	2	328	333	things aren't wrong as much as we may not like the circumstances or situation at the time.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
80343ee4-d5f4-436b-8645-ec5e7c443269	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	3	334	338	If we can work with them and change our relationship with them, then at least internally	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
05fe1319-74a1-4130-a650-f2484b11bad7	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	4	338	344	in those very difficult situations where we would have a greater sense of calm and clarity,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
ccb515e1-8d9d-45bb-b4bd-37f6cb204e06	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	5	344	347	so we can actually deal with them in a more constructive way.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
2143a5d4-33d8-46de-8583-95544c1e526c	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	6	349	353	Throughout my life I found those four things incredibly helpful.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
19495d4f-8085-4a44-a5d0-4513a95cec82	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	7	353	358	So if I had to choose just one thing or one group of things to teach my children, it would be that.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
0fa7cbe3-5e6d-4ac3-a977-f31db3efb626	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	8	358	361	And the truth is, this is about kids but it's not about kids.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
3a6f80f1-7349-4347-a324-ded7055be7d7	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	9	361	366	This is just another way of asking ourselves, what's most important in our life?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
1fe4d702-bc24-4165-b56a-8f39a5a47c26	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	10	366	370	And if we have to remember just one thing, what would that one thing be?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
da6eee41-c5dd-471b-9ee9-4536ae4140cf	274db4cc-7a7c-47c0-b5c1-cfbe940fe23c	11	371	375	Have a great day today, have a great week this week, thanks for listening and I'll see you back here tomorrow.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:18:58.729478+00
b1d70a65-be4e-4023-8dc8-3a794547c670	29937f7d-c2b6-4419-9244-fc66d522a2e6	0	0	3	Life doesn't always come with a pause button.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
2d52728a-d08b-4a4a-8db3-ce215d3c1cc3	29937f7d-c2b6-4419-9244-fc66d522a2e6	1	3	7	There's always something pulling your attention, someone asking for more.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
069bb1e3-9726-4305-ac5b-63745473c331	29937f7d-c2b6-4419-9244-fc66d522a2e6	2	8	11	Most days you're just moving through, trying to keep up.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
0147041c-043a-4f26-88cf-7b67b12279cf	29937f7d-c2b6-4419-9244-fc66d522a2e6	3	12	16	As the to-do list gets longer, you don't always realize how much your mind is caring.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
0515e3b4-d084-4f03-9686-319ea3fd8f95	29937f7d-c2b6-4419-9244-fc66d522a2e6	4	17	20	It's easy to forget to check in without you really doing.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
e0947ad4-4e0d-4408-9813-f65971f96e21	29937f7d-c2b6-4419-9244-fc66d522a2e6	5	21	22	But headspace can help.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
63b0c672-2100-4372-a53c-d40720c6f3dc	29937f7d-c2b6-4419-9244-fc66d522a2e6	6	23	27	Now headspace works with your Apple Watch to support your mind when your body says you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
e62e3984-b760-4a0a-a0c4-492a9b12e049	c248131e-3738-495d-b166-ff454577bcc5	0	27	28	need it.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
72084752-32f1-4eeb-8bfd-11299f2573a0	c248131e-3738-495d-b166-ff454577bcc5	1	29	32	This mental health awareness month tap into what your mind needs.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
5405ed3e-57b0-4bc9-b76c-0c9d3a4a2551	c248131e-3738-495d-b166-ff454577bcc5	2	33	38	Now that headspace works with Apple Watch, you can meditate on a walk, take a breath	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
77920883-1acc-4fd4-b014-2ed42b86caf9	c248131e-3738-495d-b166-ff454577bcc5	3	38	43	during a meeting, or stay calm while sitting in traffic, all without using your phone	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
4d224197-4c32-4fa4-b6c6-40e8f56f04c0	c248131e-3738-495d-b166-ff454577bcc5	4	43	44	screen.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
9acd3ba1-5691-42cc-be2e-38f19dfd6ae9	c248131e-3738-495d-b166-ff454577bcc5	5	44	50	And throughout your day, headspace sends gentle nudges to your Apple Watch with quick breathing	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
058c9cbe-6ca4-4fe7-8bc3-e448bc4fa0ed	c248131e-3738-495d-b166-ff454577bcc5	6	50	52	exercises to help you relax.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
789aa393-204f-4ce7-a8b1-281597b5d714	c248131e-3738-495d-b166-ff454577bcc5	7	52	56	A breath at the right time can change your entire day.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
c40d2bc6-684f-41a0-9e48-b175e410afbd	258bf44b-679e-41e5-be28-944a6935c5f4	0	56	60	Go to headspace.com to start your free trial today.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
c94be9e7-9613-4d0f-850a-eba034315ed1	258bf44b-679e-41e5-be28-944a6935c5f4	1	71	74	Hi, it's Andy here, and welcome to Radioheadspace.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
957087b5-461f-4fc0-8e1d-29b0f1b4324d	258bf44b-679e-41e5-be28-944a6935c5f4	2	74	76	And to the end of the week, Friday morning.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
8873e0ee-680e-48ea-a9c3-b4104d849e80	258bf44b-679e-41e5-be28-944a6935c5f4	3	77	81	I'd like you to take a moment today, just to think about the ways that you express creativity	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
fe1bee07-b41a-437c-996c-436e05a32b78	83c59de5-4f13-4e46-8df2-c743fdff4b92	0	81	82	in your life.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
aa41e879-5006-4d79-8ac9-60ec21d9de0a	83c59de5-4f13-4e46-8df2-c743fdff4b92	1	82	87	Maybe it's in your work, maybe it's in your spare time, maybe it's in the way that you present	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
3284c9cc-ede1-4848-867a-c1c0485ebf5e	83c59de5-4f13-4e46-8df2-c743fdff4b92	2	87	88	yourself to the world.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
eaef4db4-0b57-494f-a33c-c825dd20c1a4	83c59de5-4f13-4e46-8df2-c743fdff4b92	3	88	91	There are so many different ways of expressing creativity.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
894c85db-72c3-4270-98e1-ed3897f5b705	83c59de5-4f13-4e46-8df2-c743fdff4b92	4	91	96	And it's interesting, as we grow up over time, how those expressions change, and maybe	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
0ab3a84a-5a44-41df-83a6-459c19a14db6	83c59de5-4f13-4e46-8df2-c743fdff4b92	5	96	101	the intention and purpose behind them change, and how that even begins to influence the	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
143dfadd-b8e5-4fa3-8938-6136d12ca30b	83c59de5-4f13-4e46-8df2-c743fdff4b92	6	101	102	expression itself.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
9ff2c31f-d2b8-416f-ba15-cf495d3487f0	83c59de5-4f13-4e46-8df2-c743fdff4b92	7	103	109	So how do we get back to that real innocence, expressing creativity in a way that is without	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
7295eaff-fd29-46de-93bc-da1f122d5d91	896b424e-9fb5-45eb-846d-d0a3edf4ea41	0	109	113	any purpose, without any reason, without any expectation.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
90da4e08-0c82-4721-98e7-41153d117643	896b424e-9fb5-45eb-846d-d0a3edf4ea41	1	114	121	And it's interesting, you think maybe sort of with children that they might do that, but I	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
79654f46-594d-4a8e-b81f-f262163f6683	896b424e-9fb5-45eb-846d-d0a3edf4ea41	2	121	128	willing to experiment a lot, and there may be not making it necessarily with the intention	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
fc84b1b6-f13e-41d6-9d14-7ad2fdd63a25	896b424e-9fb5-45eb-846d-d0a3edf4ea41	3	128	130	to get approval at the same time.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
a4894bed-3f51-4877-8c89-f1372849b439	896b424e-9fb5-45eb-846d-d0a3edf4ea41	4	130	136	There is definitely an idea having expressed that thing, to then sort of seek approval for it	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
beda6cff-9c73-4baf-8d79-cf69bbc39b3e	896b424e-9fb5-45eb-846d-d0a3edf4ea41	5	136	137	and to feel better as a consequence.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
40459f6c-dca3-49f7-abf3-92c53163ed1a	896b424e-9fb5-45eb-846d-d0a3edf4ea41	6	138	143	As we get older, I think often commerce comes into play, and especially if it's for our work,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
6b9d0698-bd62-403a-b0aa-a46986aceaf3	75a983b7-97b7-49dc-9656-fdb4f0b12f36	0	143	144	we feel the need.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
e3a0584a-e8a4-419e-9155-fdda98f91411	75a983b7-97b7-49dc-9656-fdb4f0b12f36	1	145	150	There is a very real need to actually make something that other people like.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
ff3aaaa8-2f90-4c50-ac32-13222d22a6df	75a983b7-97b7-49dc-9656-fdb4f0b12f36	2	150	157	So all of a sudden, I think the expression starts to be manipulated in some ways.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
b2fdc705-90ac-4f10-aad2-3ad5c1cfb261	75a983b7-97b7-49dc-9656-fdb4f0b12f36	3	157	160	Of course, when it comes to commerce and a work, there's no real way around that.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
56a915f8-4f4d-4de0-9c77-052025d7a08f	75a983b7-97b7-49dc-9656-fdb4f0b12f36	4	161	165	That's kind of as it is, and we have to find a way in our own mind to be okay with that.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
6f8fb5b2-ba3d-42d9-817e-55da223868e8	75a983b7-97b7-49dc-9656-fdb4f0b12f36	5	165	173	But I feel it's really important in everyday life to find some way, some play, somehow,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
0cabc8e8-0074-406e-b40c-9c5b30ab2be9	75a983b7-97b7-49dc-9656-fdb4f0b12f36	6	173	180	of simply expressing ourselves in a way that feels innocent and uncontrived,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
f5774d8d-78e3-4445-ab0d-e3ee79008b23	85514b58-5cea-42da-ac15-630d53843a98	0	181	185	and the feels that brings a sense of joy to our life.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
60b6f830-fa76-426a-95be-5885d097c7a7	85514b58-5cea-42da-ac15-630d53843a98	1	185	189	It's so easy, I think, to focus on what other people like.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
977543af-0d60-4352-bc3d-b3c98be0658d	85514b58-5cea-42da-ac15-630d53843a98	2	190	194	And in doing that, we are already moving away from that expression.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
1e1024e6-fa59-4656-a7e7-858243961d73	85514b58-5cea-42da-ac15-630d53843a98	3	195	201	To be able to genuinely deliver something without any idea, without any expectation,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
324ec557-beb0-419c-b2e4-895a270507ba	19c59c3b-6c17-432a-8d6d-f169d9755e2a	0	202	205	without wanting to impress another person.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
144bc3e7-e21e-4857-891c-f7586af08e36	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	25	467	469	Thank you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
3aeb63e1-4016-4fc7-a7db-9ab51fe21580	19c59c3b-6c17-432a-8d6d-f169d9755e2a	1	205	207	As she takes real courage, it's quite difficult.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
6b1cc3d1-a051-4d99-8dc2-6968a4a5fec8	19c59c3b-6c17-432a-8d6d-f169d9755e2a	2	208	210	Now you may be thinking, well, this is crazy.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
5155cf3c-7d85-4b2d-aa70-c57e4a50aed1	19c59c3b-6c17-432a-8d6d-f169d9755e2a	3	210	214	I'm not going to sort of cook up a huge dinner for friends and invite them around and not care	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
df0309c1-ec79-4e24-8c19-d6afa108f1d5	19c59c3b-6c17-432a-8d6d-f169d9755e2a	4	214	218	whether they like it or not. Or I'm not going to, I don't know, learn a new tune on my guitar	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
50c3a80b-f0fa-43d3-a1a1-213b96ba275e	19c59c3b-6c17-432a-8d6d-f169d9755e2a	5	218	222	or piano or whatever and play it for someone else and not care what they think.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
86cac420-8f00-4e40-9e01-f97176f88483	19c59c3b-6c17-432a-8d6d-f169d9755e2a	6	222	228	But actually finding areas of life where the risk is fairly low, I think is really important.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
be699a8e-2908-4e24-9fe1-29fdc7bf0bc0	19c59c3b-6c17-432a-8d6d-f169d9755e2a	7	229	235	It reminds us of something, I think quite different is very hard to find that in other areas of life,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
7be5648b-5a56-4d22-8764-6f167771b1c6	1ce986ce-65d4-4d7f-8adc-0af66b7f60ca	0	236	241	where we have the freedom to truly express how we feel, but without any real consequence.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
6c2e43af-f7a9-49fe-8d55-c2bc240b9071	1ce986ce-65d4-4d7f-8adc-0af66b7f60ca	1	242	245	And hey, look, we don't have to start by doing it in front of others.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
0e9fca0c-a291-4709-a65c-0ecf0bf6b2cf	1ce986ce-65d4-4d7f-8adc-0af66b7f60ca	2	246	250	It might be that we begin on our own just getting comfortable with the idea,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
a26cb2ad-b412-4f3d-8177-27b4395c1250	1ce986ce-65d4-4d7f-8adc-0af66b7f60ca	3	250	255	and then maybe we share it with someone. And maybe it's something they like, maybe it's something they	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
5f51d893-af0b-4b6b-acff-e96b76af8678	1ce986ce-65d4-4d7f-8adc-0af66b7f60ca	4	255	260	don't like. Working with that, even if we perceive it as negative feedback,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
fcc113e7-c7b3-4244-bfbd-481a661d60f0	1ce986ce-65d4-4d7f-8adc-0af66b7f60ca	5	260	267	as she allows us to grow in confidence, to grow in courage, and to get back a little bit closer	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
27b7a06d-356f-4202-be61-4883ca812f14	1ce986ce-65d4-4d7f-8adc-0af66b7f60ca	6	267	272	to that idea of a natural expression of creativity.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
79639d25-1f22-4e08-93a3-6731eb4d57af	1ce986ce-65d4-4d7f-8adc-0af66b7f60ca	7	273	276	There's something to think about over the weekend, whatever you're doing, I hope you have a	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
361c5a17-a79a-40ad-83a9-4078de34313e	1ce986ce-65d4-4d7f-8adc-0af66b7f60ca	8	276	278	wonderful weekend, I'll look forward to seeing you back here on Monday.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:04.170762+00
ff028416-4e77-42d6-9088-f08c012a59d6	5c4432d1-4541-4b93-b3d9-52822f72f400	0	0	3	Life doesn't always come with a pause button.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
345e5e0d-2a20-478d-8fd7-43aa663c2e2a	5c4432d1-4541-4b93-b3d9-52822f72f400	1	3	7	There's always something pulling your attention, someone asking for more.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
f2248060-6d66-4890-9035-4f1375c1bbbf	5c4432d1-4541-4b93-b3d9-52822f72f400	2	8	11	Most days you're just moving through, trying to keep up.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
03f4e479-afe5-45fb-b565-269aa3ffabe6	5c4432d1-4541-4b93-b3d9-52822f72f400	3	12	16	As the to-do list gets longer, you don't always realize how much your mind is caring.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
dec07140-718c-4329-b060-636f016e4400	5c4432d1-4541-4b93-b3d9-52822f72f400	4	17	20	It's easy to forget to check in without you really doing.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
135371a7-d94b-4393-813a-299cbbd57cbc	5c4432d1-4541-4b93-b3d9-52822f72f400	5	21	22	But headspace can help.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
f2b79bae-a194-44a2-8e7a-a36a3c721635	5c4432d1-4541-4b93-b3d9-52822f72f400	6	23	27	Now headspace works with your Apple Watch to support your mind when your body says you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
d09fe7de-1896-422c-8113-d845d0bad7cc	a5ed8b96-7712-49cb-9e4b-d83b52f116a7	0	27	28	need it.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
8ba7add0-eb7d-45ca-b389-cac5c8a5d45e	a5ed8b96-7712-49cb-9e4b-d83b52f116a7	1	29	32	This mental health awareness month tap into what your mind needs.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
b5840c62-657e-441b-9d13-f6605cf62b65	a5ed8b96-7712-49cb-9e4b-d83b52f116a7	2	33	38	Now that headspace works with Apple Watch, you can meditate on a walk, take a breath	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
1bc17c75-0d3f-43da-b86f-d014a7cb1914	a5ed8b96-7712-49cb-9e4b-d83b52f116a7	3	38	43	during a meeting, or stay calm while sitting in traffic, all without using your phone	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
f8f336cc-cd46-4f23-b283-1169b2d96ef6	a5ed8b96-7712-49cb-9e4b-d83b52f116a7	4	43	44	screen.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
fc6220cd-f16c-44a4-bbd6-1c68247c9bca	a5ed8b96-7712-49cb-9e4b-d83b52f116a7	5	44	50	And throughout your day, headspace sends gentle nudges to your Apple Watch with quick breathing	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
19b382c6-d992-4f11-8510-4f88a8cd189e	a5ed8b96-7712-49cb-9e4b-d83b52f116a7	6	50	52	exercises to help you relax.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
be7892d7-0486-4082-8cd8-9ce9b78f22d2	a5ed8b96-7712-49cb-9e4b-d83b52f116a7	7	52	56	A breath at the right time can change your entire day.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
7f6a15f0-dbb6-482d-b5e3-c8a7b6d9a10c	81a01dfa-9fa3-426e-8ea1-1577e38a67e2	0	56	60	Go to headspace.com to start your free trial today.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
2179e76d-b8f4-4344-895d-2a2fd2925ca5	81a01dfa-9fa3-426e-8ea1-1577e38a67e2	1	73	78	Hi, it's Andy here, and welcome to Radioheadspace, until Wednesday morning.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
c72c9374-18e0-416a-b6f1-2367e593a944	81a01dfa-9fa3-426e-8ea1-1577e38a67e2	2	79	83	So I wonder if there's a part of you that you would like to change.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
4e923ef6-7af7-498d-bd85-242044cb9f4f	81a01dfa-9fa3-426e-8ea1-1577e38a67e2	3	84	89	For most of us, I think there are aspects of ourselves that we might wish were a little different.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
a6ae0c9d-bab9-4ee5-928c-ad85f4d79918	05da32ac-f08c-4846-bdfe-f07d36f2a517	0	90	95	And sometimes there might be a feeling as though it's impossible to change.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
aeedab18-606c-41ee-8401-e814bc38beb9	05da32ac-f08c-4846-bdfe-f07d36f2a517	1	95	99	And the older we get, we might assume that, well, the longer we've been alive,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
9bde1787-3abd-49bd-88fe-c0aacca7c079	05da32ac-f08c-4846-bdfe-f07d36f2a517	2	99	106	the more solid those qualities become, and therefore, the less likely it is to change.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
19d12148-e7f5-4658-8d86-27bf88734cbe	05da32ac-f08c-4846-bdfe-f07d36f2a517	3	108	110	But to that, I'd like to kind of reframe that a little differently.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
5997abb0-41a3-43dd-966c-89e26d1273ea	05da32ac-f08c-4846-bdfe-f07d36f2a517	4	111	116	And maybe offer a dilemma of hope that we can change at any age.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
92fc543d-8dad-4e64-9a47-9da83d65df9e	05da32ac-f08c-4846-bdfe-f07d36f2a517	5	116	120	And look, I say this is not only someone who's getting on in the years, but, you know, we've had	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
4f497dc1-da57-4d49-9b93-e141ef2c51fb	05da32ac-f08c-4846-bdfe-f07d36f2a517	6	120	125	people along at headspace in their 70s, 80s and 90s learning meditation and talking about	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
af3c0ee1-8c3e-4656-a448-cee1a55e88f4	05da32ac-f08c-4846-bdfe-f07d36f2a517	7	125	131	how even at that age, it's really transformed their thinking the way they feel about themselves	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
5eab5b6c-f24b-4ae5-bdc4-d7cad0ee91a9	05da32ac-f08c-4846-bdfe-f07d36f2a517	8	131	138	and about particular aspects of themselves. And I'm always fascinated by this idea of impermanence	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
b7c86476-0c1b-4ea5-9e8d-126c9d140d3d	05da32ac-f08c-4846-bdfe-f07d36f2a517	9	138	145	and change and how everything is in constant flux, all of the time. If we think about the physical	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
45097e64-fff2-4f67-a079-d78b9a8b38f9	05da32ac-f08c-4846-bdfe-f07d36f2a517	10	145	150	body, for example, okay, so more than I don't know exactly how many, but I know there's more	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
36630bd6-80d3-428b-814f-de5aebc55c01	82e32b6a-c531-4f20-aa02-50c8008aa055	0	150	158	30 trillion cells in the body and that those cells are refreshed, replaced in full every six months.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
caee4359-5c99-48fe-a368-43a9310612eb	82e32b6a-c531-4f20-aa02-50c8008aa055	1	158	163	Something like that, we're going to sort of a cycle. So even though we look at our physical	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
3af27098-0b4d-4532-b622-b78cba02cb00	82e32b6a-c531-4f20-aa02-50c8008aa055	2	163	168	body and we might assume that it is solid, that it's fixed, that it kind of is what it is.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
cd579c49-8ace-49ed-ac41-d52990eac651	82e32b6a-c531-4f20-aa02-50c8008aa055	3	168	177	Well, in truth, the entire physical body is being refreshed and replenished over that period of time.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
09ca8a87-a385-41a0-b86a-3bc8a967adf3	82e32b6a-c531-4f20-aa02-50c8008aa055	4	177	182	So then we might think, yeah, sure, but what about our thoughts and our mind? That's always the same.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
d1076885-4cf8-4184-ae1f-8c2e87276260	82e32b6a-c531-4f20-aa02-50c8008aa055	5	182	187	Well, if meditation teaches us anything, mindfulness teaches us anything. It's that the mind is never	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
cbdd2f06-b54b-4222-841f-cfb3a6c894b8	82e32b6a-c531-4f20-aa02-50c8008aa055	6	187	194	the same. Sure, we might have the same similar sort of theme thoughts that come back time and time again,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
f390ef7f-9984-4ab6-b524-f2e57a42e62a	206c85d1-07dd-48f5-ad47-098ecab12ae1	0	194	199	but it's never the same thought. It might sound identical in the mind. It may look identical	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
ca5de17c-d0e3-4fa2-b4d9-23c8b916f8be	206c85d1-07dd-48f5-ad47-098ecab12ae1	1	199	205	in the mind, but it's always within a different environment because the mind is constantly changing.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
642150ed-e8b1-4c76-8774-19f3ef45a773	206c85d1-07dd-48f5-ad47-098ecab12ae1	2	207	213	So if we're able to witness that clearly in our mind and see that thoughts are always changing,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
18830e28-ed2e-4af8-8555-e03db7d46c2b	206c85d1-07dd-48f5-ad47-098ecab12ae1	3	213	218	feelings are always changing, that our body is always changing, and that our place in the world is	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
871f682d-7f0a-4f3d-bea0-917690cd36e7	d60ca940-a5b9-4102-ad2e-046cab6fc2c3	0	218	223	always changing, then all of a sudden things don't feel so fixed, that don't feel so static.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
53200dcd-18db-4565-ac50-a0268bdf9eee	d60ca940-a5b9-4102-ad2e-046cab6fc2c3	1	224	230	There's a feeling, even if it's just a little bit, of freedom, of movement, offering us the	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
a1545ac0-6f7c-4651-b55f-f79b098c9d49	d60ca940-a5b9-4102-ad2e-046cab6fc2c3	2	230	237	possibility and the potential for change. So as you go into your day to day, as you go into the	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
6ab99328-082e-4835-b065-dc8d210b78b6	d60ca940-a5b9-4102-ad2e-046cab6fc2c3	3	237	245	rest of the week, just maintaining that idea, that there is perhaps a lot more freedom in our mind,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
15b9473d-b434-445c-a32c-f7bb675c73ab	d60ca940-a5b9-4102-ad2e-046cab6fc2c3	4	245	251	in our body, and in our life than when we often like to think. Thanks for listening today.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
e160ff51-d74a-4175-a54f-0e8a7ff4dd1e	d60ca940-a5b9-4102-ad2e-046cab6fc2c3	5	251	252	I look forward to seeing you back here tomorrow.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:07.57476+00
982d9069-5a13-448d-8266-72040751b4d7	eaade9c7-162b-4191-9849-41bcce1db700	0	5	10	Hey everybody, welcome back for another episode of the five-minute Disoppoship podcast.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
9726f2c3-00e8-4fdd-8f91-3b3247560fc7	eaade9c7-162b-4191-9849-41bcce1db700	1	11	17	My name is Lauren Higgs and on this podcast I share five-minute episodes to help you grow	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
5f589f9c-9921-421c-a767-433d16f529e7	eaade9c7-162b-4191-9849-41bcce1db700	2	17	17	in your faith.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
dca02033-3eb4-4210-897f-7929117dff5a	eaade9c7-162b-4191-9849-41bcce1db700	3	18	22	This podcast is about discipleship and spiritual growth.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
a0ad8937-157d-406f-9c74-c9bbc9a877cf	eaade9c7-162b-4191-9849-41bcce1db700	4	22	28	It's my prayer that the short episodes inspire you and encourage you to be a fully devoted	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
a5ec5cc1-6681-4f1e-bdd4-cfc6486b89df	eaade9c7-162b-4191-9849-41bcce1db700	5	28	30	follower of Jesus Christ.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
45efedc1-9e73-4cfa-8e4a-2ce38b9d4a64	eaade9c7-162b-4191-9849-41bcce1db700	6	30	36	So if you're new to the podcast let me invite you to subscribe on your favorite podcast app	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
c636dc7f-afb3-4676-9b6c-109786c9fdac	8143135c-7e6b-49ee-b881-f93fe8e8a45d	0	36	38	so that you can join us each day.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
f6fd34e6-9823-4639-a141-566903350346	8143135c-7e6b-49ee-b881-f93fe8e8a45d	1	39	43	Today on the podcast we are talking about when God stands beside you.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
0e67eb86-190c-4a61-a5ae-c7b649bbb6d4	8143135c-7e6b-49ee-b881-f93fe8e8a45d	2	48	53	It's been said that a real friend is one who walks in when the rest of the world walks out.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
8a582479-5f01-428b-b219-111cf982f923	8143135c-7e6b-49ee-b881-f93fe8e8a45d	3	54	56	Have you ever had a friend like that?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
ac7f4855-c125-4466-8d9a-4023220a9b68	8143135c-7e6b-49ee-b881-f93fe8e8a45d	4	57	61	Perhaps you had a season in your life when it felt as if everyone was against you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
b557892d-52d9-4a9b-a442-c012c85c2f22	8143135c-7e6b-49ee-b881-f93fe8e8a45d	5	61	63	and that you were all alone.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
4085acb0-2cbb-41be-aaea-87da8ce8e897	8143135c-7e6b-49ee-b881-f93fe8e8a45d	6	63	69	Proverbs chapter 18 verse 24 says there is a friend who sticks closer than a brother.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
ccf794dd-22ad-4568-92e1-5d1a8745619a	8143135c-7e6b-49ee-b881-f93fe8e8a45d	7	69	71	I want you to know Jesus is that friend.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
3b3d2e2e-a166-47c5-a50f-eccf2a1e34b7	db0f8227-6589-48fe-8872-2ca1431234db	0	72	77	When everyone leaves, when you feel abandoned and when there is no one else around,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
617813f5-7db4-485c-9efa-cbb964197704	db0f8227-6589-48fe-8872-2ca1431234db	1	77	79	God will remain present in your life.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
1d4481b1-7eed-4daf-99e5-c7d79cbfdaa5	db0f8227-6589-48fe-8872-2ca1431234db	2	80	84	In fact, he has promised in scripture that he will never leave us, nor forsake us.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
5472c02d-7c5b-4787-b8f6-1d99791364ad	db0f8227-6589-48fe-8872-2ca1431234db	3	85	90	You know, in second Timothy chapter 4 the apostle Paul is writing about his defense of the gospel	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
5c50c2f9-fbf1-412a-8842-f5a672e06e60	db0f8227-6589-48fe-8872-2ca1431234db	4	90	91	as a prisoner in Rome.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
3ef97557-2529-4e6d-b016-36f84d40bee3	db0f8227-6589-48fe-8872-2ca1431234db	5	91	98	He talks about how everyone abandoned him and he was left alone as he stood before the Roman authorities.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
bf2b42d8-4aa0-41b5-b41d-209780bf488b	db0f8227-6589-48fe-8872-2ca1431234db	6	99	103	This reminds me of how the disciples of Jesus fled after his arrest.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
a6e7364e-b589-4a7f-845f-60c7ebee1226	db0f8227-6589-48fe-8872-2ca1431234db	7	104	108	But listen to what Paul says, second Timothy chapter 4 verse 16 and 17.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
1a842a5f-c882-4406-b8d7-cebe9ea6390d	00841ccf-9eda-4b03-ad0a-74fe6efe9d08	6	103	107	I get frustrated, I complain, sometimes I get upset.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
d6f1f75a-b6c6-4ef3-9529-cfafe9aa59b4	db0f8227-6589-48fe-8872-2ca1431234db	8	109	114	At my first defense no one came to my support, but everyone deserted me.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
a8f4ba22-f44b-4cdd-89df-0151f8d07e2d	db0f8227-6589-48fe-8872-2ca1431234db	9	114	119	May it not be held against them, but the Lord stood at my side and gave me strength.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
75ae6ecd-25af-40e6-af21-78d1f0a5c387	db0f8227-6589-48fe-8872-2ca1431234db	10	119	126	So that through me the message might be fully proclaimed and all the Gentiles might hear it.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
8c2aa1fb-8c2e-40e5-b2b4-93390921c6fa	db0f8227-6589-48fe-8872-2ca1431234db	11	126	131	How discouraging it must have been for Paul that not even his closest friends would be with him,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
e22212cf-179f-48c9-a288-94d23a005e64	db0f8227-6589-48fe-8872-2ca1431234db	12	132	134	during one of his most difficult days.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
63dd85d9-03d7-41ca-80e9-e605827cefdc	143f1bf0-cc19-4f8d-b26c-ea90908b06b2	0	134	137	Yet Paul acknowledges the presence of God.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
3d85ef54-54cd-4208-be83-85c7f86012ff	143f1bf0-cc19-4f8d-b26c-ea90908b06b2	1	137	140	He said the Lord stood at my side and gave me strength.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
7b9bbb06-b323-4a45-b468-11ad83e5d630	143f1bf0-cc19-4f8d-b26c-ea90908b06b2	2	141	143	All he had was God, but that was all he needed.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
aaf2c218-8aa1-4bb8-8de9-a42b3b66f1f8	143f1bf0-cc19-4f8d-b26c-ea90908b06b2	3	144	148	Like the apostle Paul, you might be facing one of your most difficult situations.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
0d2ef67b-5177-4a60-b8be-bff184a44a5f	143f1bf0-cc19-4f8d-b26c-ea90908b06b2	4	149	154	Maybe you are facing it all alone and you wonder where your family and friends are.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
cb5a4acb-adf0-469a-809f-90f862db9bdc	143f1bf0-cc19-4f8d-b26c-ea90908b06b2	5	154	156	Perhaps it seems that no one understands.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
46685e96-9a58-4e23-ba33-ca8d434872cd	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	0	157	159	How want you to receive this truth today?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
471dfcc6-e2a0-44dc-b31c-c13a1525c5fd	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	1	160	162	God is standing beside you.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
c0603185-2ffe-4340-bbf3-e0826323a8ec	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	2	162	164	He is there. Can you acknowledge his presence?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
9ad66e6c-2bbc-4b2c-95a6-2e9e8146002c	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	3	165	167	Everything you need he will provide.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
5b2c287e-e252-402e-905b-2150636991c3	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	4	168	172	Repeatedly in the Bible he promises us that he will be with us.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
82cc341e-5da3-405d-a7da-61318f4cdda3	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	5	172	174	Listen to Isaiah chapter 41 verse 10.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
ae52a7ce-b10f-4baf-b6eb-644fcb7b0c6f	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	6	174	178	The Bible says, don't be afraid for I am with you.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
7f905eb1-675c-480f-ae67-407447de5062	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	7	178	181	Don't be discouraged for I am your God.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
b31e8609-ee60-4935-8ca7-57424eccc6af	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	8	181	183	I will strengthen you and help you.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
621040c2-f20d-419d-9213-37ba99a505bb	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	9	183	186	I will hold you up with my victorious right hand.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
f3e43a49-e687-4b73-9348-37e7f5283d97	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	10	187	189	In Deuteronomy chapter 31 verse 8 says,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
321f6611-0866-4868-88a7-95b62e24efda	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	11	190	195	Do not be afraid or discouraged for the Lord will personally go ahead of you.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
408029a6-370a-4f20-b0bf-d03f9aa01788	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	12	195	199	He will be with you. He will neither fail nor abandon you.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
0fa7d0e9-e78b-4901-a81c-3267c3d358a9	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	13	200	205	What I love about the Bible are the real-life stories of people who faced all kinds of difficulty	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
b721af10-9831-42ba-ba84-dc21b47d983f	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	14	205	210	and adversity. We learn of their struggles spiritually, emotionally, and physically.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
68f37165-09b5-446d-9735-dae42918999a	448c33cb-d3bc-45e5-b2dc-15b481bd9ff4	15	210	213	But we also see God at work in their lives.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
8cf69bde-162b-4897-b444-10287528126d	f508a024-399c-4333-89af-2c98e3411cf9	0	213	218	We learn of God's faithfulness. We see God's compassion, wisdom, and guidance.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
08340deb-cc6c-4f7e-ba3b-dfdeb580d651	f508a024-399c-4333-89af-2c98e3411cf9	1	219	224	We discover he is a God who loves his people and one who will never abandon them.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
ef58d0ea-8eb8-4c62-9021-d5707ea63a4f	f508a024-399c-4333-89af-2c98e3411cf9	2	225	229	You know, in my own life it is the presence of Jesus that has made such a difference.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
145fc9f5-c525-4636-a4dd-0392372c967a	f508a024-399c-4333-89af-2c98e3411cf9	3	230	232	Had I faced my battles alone?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
6513ed46-bd5f-40c4-aa6e-cc00060e6faa	c1822876-0f14-4cb4-a279-b379115292a8	0	232	236	I don't know how I could have survived, but I can say like the Apostle Paul,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
e019f90d-936d-4927-8b01-5aeaa1b9cf8b	c1822876-0f14-4cb4-a279-b379115292a8	1	237	240	the Lord stood at my side and gave me strength.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
71ab14d6-28e7-4d65-bd19-edd4e8a20f89	c1822876-0f14-4cb4-a279-b379115292a8	2	241	243	Perhaps today you are facing a physical illness.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
f19b9f9e-d92d-49bc-8f14-c2b4d2865038	c1822876-0f14-4cb4-a279-b379115292a8	3	244	248	Maybe you are stuck at home in a hospital or a nursing home and you feel all alone.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
2e8173ae-3614-46e1-a5a6-f3e494011017	c1822876-0f14-4cb4-a279-b379115292a8	4	249	253	Possibly you are dealing with merit of conflict or abandonment by your children.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
274793f7-441c-4635-bb92-da6ed35d0809	c1822876-0f14-4cb4-a279-b379115292a8	5	254	259	Maybe you feel beaten down by financial struggles overwhelmed by stress at work or anxious	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
e459720e-c5ca-4829-90d9-52bca0757755	c1822876-0f14-4cb4-a279-b379115292a8	6	259	266	about your future. Receive this encouragement. God is standing at your side and he will give you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
5567a3fb-f509-4c03-ac9b-5d5a891ced10	c1822876-0f14-4cb4-a279-b379115292a8	7	266	272	strength. There is nothing you are facing that God cannot handle. There is no need in your	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
d60324d7-c6d6-47bd-b809-92189c1d08dc	c1822876-0f14-4cb4-a279-b379115292a8	8	272	279	life. God cannot meet. There are no problems. God cannot solve. The eternal God is standing	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
02d26536-8fd6-49cd-aa82-9a0db0a9a287	c1822876-0f14-4cb4-a279-b379115292a8	9	279	285	beside you right now. And here's today's challenge. Set aside a few minutes to acknowledge God's	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
aa95ccac-1e8e-43f6-b8e6-1563c0495af4	c1822876-0f14-4cb4-a279-b379115292a8	10	285	292	faithful presence in your life. Thank you that he has always been with you and that he always	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
262465d9-46b4-4558-84de-f83054cef7c7	c1822876-0f14-4cb4-a279-b379115292a8	11	292	298	will be. Hey, thanks again for joining me for today's episode. I hope you have a wonderful day.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
d84393fb-f610-4093-8e51-94a495005180	c1822876-0f14-4cb4-a279-b379115292a8	12	299	304	And until next time, let's continue on our journey as followers of Jesus.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:10.924563+00
f9828835-86fa-4b41-8a6a-24c0d43d9bdf	06234d44-36df-41e1-84c8-8b8530cd72f3	0	5	10	Hey everybody, welcome back for another episode of the five-minute discipleship podcast.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
8e882f2c-8f2c-4345-8ba9-a6cbf42dda79	06234d44-36df-41e1-84c8-8b8530cd72f3	1	11	16	My name is Lauren Hicks, and on this podcast, I share five-minute episodes to help you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
a754d03e-2033-4d0e-bf05-e2e70062cbb2	06234d44-36df-41e1-84c8-8b8530cd72f3	2	16	17	grow in your faith.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
6347b6a6-af9f-4a89-b78d-eb978579ab33	06234d44-36df-41e1-84c8-8b8530cd72f3	3	18	21	This podcast is about discipleship and spiritual growth.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
86232984-565f-4be3-b71a-2e69bcdb146f	06234d44-36df-41e1-84c8-8b8530cd72f3	4	22	27	It's my prayer that these short episodes inspire you and encourage you to be a fully devoted	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
56118790-118b-4522-8275-6d7ecea5ee7c	06234d44-36df-41e1-84c8-8b8530cd72f3	5	27	29	follower of Jesus Christ.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
505be93a-14e2-41a4-a37b-138057b72096	06234d44-36df-41e1-84c8-8b8530cd72f3	6	30	34	So if you're new to the podcast, let me invite you to subscribe on your favorite podcast	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
c23f6f6e-bdad-4aca-a246-74069a8e31d9	325015cb-4dc6-4683-9d20-921e2e1a1266	0	34	37	app so that you can join us each day.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
8f91f292-170a-445f-8d84-e612badf3728	325015cb-4dc6-4683-9d20-921e2e1a1266	1	38	42	Today on the podcast, we are talking about the ministry of encouragement.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
1ceedea4-db8d-4468-9f29-50aefdf4114a	325015cb-4dc6-4683-9d20-921e2e1a1266	2	47	53	Early in my ministry, as I pastor to small church in West Texas, my wife and I met an elderly	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
8291eae1-004f-4fcc-9aad-3784b36da942	325015cb-4dc6-4683-9d20-921e2e1a1266	3	53	54	woman named Thelma.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
81ce6ef4-aef2-4a0a-a1f6-6e469e4cae6c	325015cb-4dc6-4683-9d20-921e2e1a1266	4	55	59	She was now laid in life, but had served God since she was a child.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
32c254b0-0d86-4026-8840-5c4805f77689	325015cb-4dc6-4683-9d20-921e2e1a1266	5	59	64	While she did not attend our church, she felt called by God to be a blessing to my wife	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
a02fdda7-1372-49bc-8b19-3bc01faab6db	325015cb-4dc6-4683-9d20-921e2e1a1266	6	64	64	and I.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
11b1e945-6818-4a71-9b8a-f1214917fd98	325015cb-4dc6-4683-9d20-921e2e1a1266	7	64	70	We were in our 20s, pasturing our first church, and by divine appointment, God connected	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
7a91cc44-e195-42fe-addb-1201317283fe	325015cb-4dc6-4683-9d20-921e2e1a1266	8	70	71	us to this precious woman.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
2b24c2a2-70c5-41cf-b785-e389e4d9fe4a	325015cb-4dc6-4683-9d20-921e2e1a1266	9	72	76	Throughout our years at the church, she fulfilled her calling by being an encouraged	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
ac3ca68d-7bdf-44df-b782-3f1605422d5d	730b38f5-355f-48b9-937d-f10e19cf0492	0	76	78	your to my wife and I.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
2cccdaa7-bb3b-4a95-a595-72e577cb2ef1	730b38f5-355f-48b9-937d-f10e19cf0492	1	78	83	She would often invite us over for dinner, pray for us, and share words of encouragement	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
85041b4d-bb60-455b-a77a-3aa05e7482bf	730b38f5-355f-48b9-937d-f10e19cf0492	2	83	84	the Lord had given her.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
b603d124-4f58-458b-9d53-76571ed4e583	730b38f5-355f-48b9-937d-f10e19cf0492	3	85	88	I cannot tell you what a blessing this woman of God was to my family.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
4c980084-7a46-4210-b502-dcb3a4bada12	730b38f5-355f-48b9-937d-f10e19cf0492	4	88	93	I can't remember a time being in her presence that I was not encouraged.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
85cc0e90-c59a-46ba-aa8a-dca68c291ec9	730b38f5-355f-48b9-937d-f10e19cf0492	5	94	96	Have you ever had an encourager in your life?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
01737a7c-cd11-4ad3-a237-d852ecad1f18	730b38f5-355f-48b9-937d-f10e19cf0492	6	97	101	Someone that whenever you were around them, you found your spirit lifted.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
48f443bf-d9c7-4f99-9eb3-7235306927f0	730b38f5-355f-48b9-937d-f10e19cf0492	7	101	104	This is the kind of person I want to be.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
24b57733-18b4-429a-ab84-69abe678ffd3	730b38f5-355f-48b9-937d-f10e19cf0492	8	104	106	I want to be an encourager.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
5affdfce-875b-458a-8086-f08e0c0d9749	730b38f5-355f-48b9-937d-f10e19cf0492	9	107	109	You know, in the New Testament, there is a man named Barnabas.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
45f03f91-b309-4b08-8fea-d05cca561e77	730b38f5-355f-48b9-937d-f10e19cf0492	10	110	115	He was a leader in the early church and a partner with the Apostle Paul on some of his	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
8e63472e-2d2b-4dea-9a86-b7f1cd040765	730b38f5-355f-48b9-937d-f10e19cf0492	11	115	115	missionary journeys.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
aaaf8d39-66e1-4392-b722-d761c6529d66	730b38f5-355f-48b9-937d-f10e19cf0492	12	116	121	But we learned something important about him in Acts 4 verse 36, which says, Joseph	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
6bfd8332-aa2f-4e1e-8029-1b5a4bdfd80e	730b38f5-355f-48b9-937d-f10e19cf0492	13	121	128	a Levi from Cyprus whom the Apostles called Barnabas, which means son of encouragement.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
b46c1521-09b5-4ee1-a623-321f8e5d46e0	730b38f5-355f-48b9-937d-f10e19cf0492	14	129	133	His real name was Joseph, but he was given a nickname by the Apostles.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
3c54fe86-125f-4fe5-b7d5-6bafc007ea1a	ab57e0ee-1415-4b89-b057-6cd5710f20c3	0	133	137	They called him Barnabas, which meant son of encouragement.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
829cfadf-67bb-4e34-864b-2f5c6c9c2c92	ab57e0ee-1415-4b89-b057-6cd5710f20c3	1	138	143	He was affectionately given this nickname because he had the ministry of encouragement.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
5498a514-94c7-4045-b141-f27c5b25b5e9	ab57e0ee-1415-4b89-b057-6cd5710f20c3	2	143	149	As we read the book of Acts, we see that Barnabas was an early disciple in the New Testament	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
5da99166-70c7-4a81-897d-76be89f0598e	ab57e0ee-1415-4b89-b057-6cd5710f20c3	3	149	149	church.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
074645c1-39c3-49dc-b7b0-2e7da522170e	ab57e0ee-1415-4b89-b057-6cd5710f20c3	4	149	155	He was a Levi from Cyprus and island in the Mediterranean Sea about 60 miles off the	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
03a235aa-3e0f-4265-a339-f1aa0acfe497	ab57e0ee-1415-4b89-b057-6cd5710f20c3	5	155	155	coast of Israel.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
557e56b0-9799-46c8-832f-64126b3af69b	ab57e0ee-1415-4b89-b057-6cd5710f20c3	6	156	161	Barnabas later visited the island of Cyprus on the first missionary journey with the	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
0e91c078-ae94-47bc-aee2-03868e9d3195	6c105bc0-178a-46d9-a1ed-2c987616ae18	0	161	164	Apostle Paul and again on a second journey with Mark.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
b0493c2d-8b25-435e-bea6-1b7e3d930e7a	6c105bc0-178a-46d9-a1ed-2c987616ae18	1	165	169	When Barnabas became a Christian, he sold his land and gave the money to the Jerusalem	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
e0fa0db6-b10a-49b7-b540-972fc4b0e336	6c105bc0-178a-46d9-a1ed-2c987616ae18	2	169	170	Apostles.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
03ed8cdc-31d8-47f7-aac3-59475778993b	6c105bc0-178a-46d9-a1ed-2c987616ae18	3	170	175	Early in the history of the church, he went to Anniac to check on the growth of the Christians	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
21ca4ad3-bf12-4136-8fc6-f2b1406e7f75	6c105bc0-178a-46d9-a1ed-2c987616ae18	4	175	177	there and then on to Tarsus.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
febb9966-fc59-4d29-aea0-c38cb6dfa8f2	6c105bc0-178a-46d9-a1ed-2c987616ae18	5	177	182	From there, he brought Saul, later named Paul, back to Anniac to help with the church	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
6118ab25-b9d8-43e6-987d-c614a83833bc	6c105bc0-178a-46d9-a1ed-2c987616ae18	6	182	186	in that city, which was the third largest in the Mediterranean world.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
69c69592-9a59-4230-9c73-fa4160bb082e	6c105bc0-178a-46d9-a1ed-2c987616ae18	7	187	190	Think about the influence and impact of this one man.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
99f6f5ee-857a-4e0b-a74f-a6978b54007b	d61399a3-e22c-465d-b45d-4ccf0c270667	0	190	195	With a huge heart for God and people, Barnabas finds Saul believing that God has a plan	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
69e1e639-5426-4055-88e1-0e96d71c8181	d61399a3-e22c-465d-b45d-4ccf0c270667	2	196	200	He brings him to Anniac and includes him in the ministry of the local church.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
e65c44f3-543d-4114-846b-3775ba0f335c	d61399a3-e22c-465d-b45d-4ccf0c270667	3	201	207	Saul later becomes the Apostle Paul who would plant churches all across Asia Minor	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
ae0ac5a7-25f4-43cc-927f-16afe23ac158	d61399a3-e22c-465d-b45d-4ccf0c270667	4	207	209	and would write two thirds of the New Testament.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
8f6d34fc-0289-42ed-a06f-aca56714a450	d61399a3-e22c-465d-b45d-4ccf0c270667	5	210	212	So let's think about this.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
33d73f39-2347-4907-bc2f-81f68f0e6b44	d61399a3-e22c-465d-b45d-4ccf0c270667	6	212	215	What if Barnabas had not been an encourager?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
e34404d4-a478-44f3-9fbe-c80ee8eedd6b	d61399a3-e22c-465d-b45d-4ccf0c270667	7	215	218	What if he had not obey God to reach out to Saul?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
95dbcb48-a74a-4dfe-aa39-255cf28fc6da	d61399a3-e22c-465d-b45d-4ccf0c270667	8	219	223	You never know the impact of your kindness, your love and your words of encouragement.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
e0ced6c1-c181-46bc-81d7-96c95a846be7	d61399a3-e22c-465d-b45d-4ccf0c270667	9	224	227	I believe people around you today are desperate for encouragement.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
314e746d-d79f-496b-97e9-8a16f4515574	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	0	228	231	Everyone around you is fighting about it, you know nothing about.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
207a471f-ac25-4ad0-86cc-d9cc3d3ac66e	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	1	232	236	What if difference you could make in someone's life by encouraging them to trust the Lord	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
59a3b74a-fb24-4556-b0be-20f0ae84a348	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	2	236	239	to keep believing and to not give up?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
2242c329-96d2-4447-8fa9-03beff3ce55d	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	3	240	245	What if difference you could make by encouraging someone to obey God to step out and faith	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
3f95efd4-a6b0-4592-bf07-9970dc9f5a3e	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	4	245	247	and to let God use their lives?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
50169de1-48ef-4398-98dc-189e8aa4d209	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	5	248	250	First, that's Elonian chapter 5 verse 11 says,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
6e5f5ed6-8181-4093-9e79-8494758794a0	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	6	250	254	encourage one another and build each other up.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
5e22ed1e-0292-4837-b180-630b848cc1d4	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	7	254	257	Hebrews chapter 10 verses 24 and 25 say,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
9077c1a5-e76c-47d6-89d3-1b2a8610511d	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	8	258	262	let us think of ways to motivate one another to acts of love and good works.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
6431fc41-7335-4767-8ca2-32f39ad2eec8	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	9	262	266	And let us not neglect our meeting together as some people do,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
c926a725-7b2d-4d1c-9c63-8064445660ac	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	10	266	267	but encourage one another,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
981009a0-979a-423a-b513-6ea36359f1b9	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	11	268	271	especially now that the day of his return is drawing near.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
9bc792ae-4504-4114-bb51-f77b4cfcdbb5	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	12	272	273	And here's today's challenge.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
babb027f-f2af-48d6-90f3-f3c6abd9b7f9	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	13	274	276	I believe every believer has a ministry.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
dbf0f36e-3634-4479-9ecb-96af9d644618	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	14	277	280	Don't overlook the importance of being an encourager.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
05843de1-b8ec-4885-a04d-58d5780db213	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	15	281	285	It cost you nothing but your love, your kindness, and your time.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
19c1e527-503c-4165-aeb4-ae15f49f513e	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	16	285	288	Hey, thanks again for joining me for today's episode.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
7547af61-5d8b-49ce-85af-2fcc8a2d8d04	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	17	288	292	I hope you have a wonderful day and until next time,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
cf28ad44-2ae2-4e04-871b-204209ae0afe	afe359a4-a5a9-4c34-a59d-fb014f9f2f92	18	292	295	let's continue on our journey as followers of Jesus.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:14.997582+00
4891efd3-f4fe-452b-b035-3a9e7601d230	af85381a-ffa7-4b6d-9e6d-b0efe88423e6	0	5	10	Hey everybody, welcome back for another episode of the Five Minute Disoppership podcast.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
46025faf-4e3a-4908-a58f-7c9fafc84137	af85381a-ffa7-4b6d-9e6d-b0efe88423e6	1	11	17	My name is Lauren Hicks and on this podcast I share five minute episodes to help you grow in your faith.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
3ee73452-9953-4073-bb23-669b747f36eb	af85381a-ffa7-4b6d-9e6d-b0efe88423e6	2	18	21	This podcast is about discipleship and spiritual growth.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
15e1d158-4907-4700-bf3e-246cda357039	af85381a-ffa7-4b6d-9e6d-b0efe88423e6	3	21	29	It's my prayer that these short episodes inspire you and encourage you to be a fully devoted follower of Jesus Christ.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
b554fda2-079c-45a4-ad6c-2302aaf3f449	9ed54caf-a59d-4c92-97cc-cce813657c2d	0	29	34	If you're new to the podcast, let me invite you to subscribe on your favorite podcast app,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
a0e5d2e9-6782-4192-8c00-a347402243c5	9ed54caf-a59d-4c92-97cc-cce813657c2d	1	34	36	so that you can join us each day.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
acace543-b4b9-4b2f-8d46-460587161210	9ed54caf-a59d-4c92-97cc-cce813657c2d	2	37	42	Today on the podcast we are talking about when God interrupts your plans.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
16f4c5ba-dba8-469e-a1b5-b906764ab2e8	9ed54caf-a59d-4c92-97cc-cce813657c2d	3	47	49	Recently, God interrupted my plans.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
20901da5-0612-4ddb-9aee-70403e03256f	9ed54caf-a59d-4c92-97cc-cce813657c2d	4	50	51	Has this ever happened to you?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
4ba72890-0056-4517-af39-cee850587495	9ed54caf-a59d-4c92-97cc-cce813657c2d	5	52	56	I had made plans and to me, they seemed like really good plans.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
1c97f547-9371-4927-816d-667616fab493	9ed54caf-a59d-4c92-97cc-cce813657c2d	6	57	61	But then suddenly and without warning, God closed a door before me.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
4351b28c-2298-4608-990e-e45cb1e19233	9ed54caf-a59d-4c92-97cc-cce813657c2d	7	61	63	It was completely unexpected.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
a4151aed-eeff-4e7f-a043-9f5a7e1b7cbf	9ed54caf-a59d-4c92-97cc-cce813657c2d	8	63	70	I'm not sure what God is going to do in this situation, but it is clear to me that he has interrupted my plans.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
4f6cf48d-0f58-4443-80f7-bfab941b40eb	9ed54caf-a59d-4c92-97cc-cce813657c2d	9	71	77	You see, my life is filled with interruptions, inconveniences, frustrations and unexpected events.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
ee895c8f-92be-4add-a216-0517334919a3	00841ccf-9eda-4b03-ad0a-74fe6efe9d08	0	78	80	Sometimes things break, accidents happen.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
5b7740dc-7f19-4ed1-9670-3284a950074d	00841ccf-9eda-4b03-ad0a-74fe6efe9d08	1	81	83	The phone will ring just as I climb into bed.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
d5b1c29d-9a1a-4b37-9aec-e09e13a689c6	00841ccf-9eda-4b03-ad0a-74fe6efe9d08	2	84	90	Traffic sometimes makes me late and just when I don't need another added expense and appliance will break.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
909bc0d3-3705-4d13-9635-2a5641ec16c3	00841ccf-9eda-4b03-ad0a-74fe6efe9d08	3	90	94	Unexpected illnesses change my carefully crafted plans.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
c9029ad7-814f-4c7b-9652-c1c72ca8f905	00841ccf-9eda-4b03-ad0a-74fe6efe9d08	4	95	98	I could go on and on and you probably could too.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
2859c37c-c443-4760-b8f8-456f45698785	00841ccf-9eda-4b03-ad0a-74fe6efe9d08	5	99	102	My problem is that I often handle these interruptions poorly.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
9fd35fb6-26e0-4f3a-8eaa-c74db05f95ed	00841ccf-9eda-4b03-ad0a-74fe6efe9d08	7	108	113	Though these interruptions are unexpected and catch me off guard, they do not catch God off guard.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
8b6530d8-cb71-45d9-8e56-9a67cf3d1dbc	92079ca8-1375-4cfc-a01a-a51d015ab002	0	114	116	They are not random, meaningless events.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
4cdb611f-eff0-4cde-a66e-bb73b1a1064b	92079ca8-1375-4cfc-a01a-a51d015ab002	1	116	121	In fact, these interruptions are divinely placed in my path for a reason.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
cb5fbff1-79aa-4338-b167-64ea31304473	92079ca8-1375-4cfc-a01a-a51d015ab002	2	122	126	God will use these interruptions to change me to be more like Christ.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
7fa41070-2379-471f-b638-87ad9b183dc2	92079ca8-1375-4cfc-a01a-a51d015ab002	3	127	132	An interruption can be God's tool to help us become more patient, more loving and more understanding.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
d6708173-59ed-40af-b511-cce892567869	92079ca8-1375-4cfc-a01a-a51d015ab002	4	133	137	It can be God's way of guiding our steps and pointing us in the right direction.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
1e8e5c94-7b9e-41bd-99aa-9b9be0a85649	92079ca8-1375-4cfc-a01a-a51d015ab002	5	138	143	Divine interruptions can be God's hand-a-protection in our lives when we are starting to move in the wrong direction.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
36442d5b-d9f0-4442-bbde-92b83684e2a3	92079ca8-1375-4cfc-a01a-a51d015ab002	6	143	147	God's interruptions are always for a reason.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
ae7858d4-261d-4a84-a7b9-0f720f1374df	92079ca8-1375-4cfc-a01a-a51d015ab002	7	148	155	You know, as you read the Gospels, you can't help but notice that Jesus himself was interrupted and just about every day.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
3aaf5866-c265-4523-8f5e-97bae40010cb	92079ca8-1375-4cfc-a01a-a51d015ab002	8	155	161	There was always someone reaching out to him for healing, deliverance, provision, or simply a question.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
5e8e8356-1fb9-4ad2-ad7d-e3b1dcf6a35d	92079ca8-1375-4cfc-a01a-a51d015ab002	9	161	167	But then we see Jesus embracing the interruptions and serving those he came in contact with.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
a016316e-030f-49eb-8aca-a9679b0e87a5	92079ca8-1375-4cfc-a01a-a51d015ab002	10	167	174	For Jesus, the interruptions did not stop his ministry, the interruptions became his ministry.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
89db6024-ad3c-4bc2-b7a3-6d87cf69605f	5045115e-d882-4ce8-b223-6eb5052456ea	0	175	179	Divine interruptions remind us that our knowledge and perspective is very limited.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
2450e09d-4968-4bc2-b77d-9b28014ba290	5045115e-d882-4ce8-b223-6eb5052456ea	1	180	182	We cannot see and know as much as God.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
0a8ca674-0b62-4d13-8039-f95045e1d63e	5045115e-d882-4ce8-b223-6eb5052456ea	2	183	190	So we surrendered to his plan, recognizing that we serve a God who has all knowledge and he knows what is best for us.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
1635445f-2945-4117-898d-47e533194487	5045115e-d882-4ce8-b223-6eb5052456ea	3	190	195	So if interruptions are God's plan for us, we must embrace them.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
3121e3cc-5c4d-4c8d-b3ee-146e5f44b078	5045115e-d882-4ce8-b223-6eb5052456ea	4	195	203	Proverbs chapter 19 verse 21 says, many are the plans in a man's heart, but it is the Lord's purpose that prevails.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
96154b49-6ef8-4900-8bcd-9fc2b5b276f3	88b0395b-ea76-4bbb-a9fd-b115032aa393	0	204	212	And I like Proverbs chapter 16 verse 9 which says, the heart of man plans his way, but the Lord establishes his steps.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
5785130f-d2d3-49fb-8559-27a3cf910e82	88b0395b-ea76-4bbb-a9fd-b115032aa393	1	213	218	So what do we do when we are interrupted and we sense that God is at work in the interruption?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
43cc796e-4a53-43ef-a6d8-774f20c983ef	88b0395b-ea76-4bbb-a9fd-b115032aa393	2	218	221	First let me encourage you to pause and take a breath.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
40eb05c9-1eeb-4b50-84ae-a16a2456c02d	88b0395b-ea76-4bbb-a9fd-b115032aa393	3	222	228	It's so easy to become irritated and reactive when we face the frustration of an interruption.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
ce67a376-20bd-40bc-bb87-0eacd5ba36dd	88b0395b-ea76-4bbb-a9fd-b115032aa393	4	228	233	Second, pray and ask God to help you be aware of what you need to see.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
4bdbda17-adff-48f3-90a9-05a9b42cfcc9	88b0395b-ea76-4bbb-a9fd-b115032aa393	5	233	235	Ask the Lord to open your eyes to his direction.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
6799a582-ed2f-47b7-ae6d-0e3c7f244d24	0d7642c8-eb70-4b87-b836-f4937b7b1d2b	0	236	239	Because of the interruption, there may be no clear path forward.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
df674cb3-7eab-443d-bdd9-239697c0b537	0d7642c8-eb70-4b87-b836-f4937b7b1d2b	1	240	245	In these instances, we have the opportunity to wait upon God and seek his direction.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
ddbf2c98-7e4c-4349-8192-cc8bbed38d24	0d7642c8-eb70-4b87-b836-f4937b7b1d2b	2	245	249	Remember, waiting on God is never wasted time.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
acff9adf-b672-41b8-8661-e45840faf0aa	0d7642c8-eb70-4b87-b836-f4937b7b1d2b	3	250	253	Third, be alert to the possibility of discouragement.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
a7645487-fb8e-4e65-a5c8-1354e233beef	0d7642c8-eb70-4b87-b836-f4937b7b1d2b	4	253	260	When our plans don't work out when the door is shut in front of us and when we cannot move forward, it's so easy to become disappointed.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
094dbd57-8780-4369-9268-c2ce303c052f	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	0	262	266	Becoming discouraged is a choice. Don't give into it. Praise God anyway.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
e1136e73-6420-4366-8e2d-0bc8ec79688e	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	1	267	272	Trust God is working in the interruption and that a testimony is coming soon.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
5ca5fc27-a6c1-4f72-a0b3-b95cb29feead	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	2	272	280	It has been said that a man's greatness is measured not by his talent or his wealth, but by what it takes to discourage him.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
3422f9c9-925c-4dfc-a678-8bd0d77fd66a	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	3	280	282	So choose not to be discouraged.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
8a4ff8f6-c630-4f3d-819f-43d3e2aef6d8	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	4	283	288	And remember this great truth from Romans chapter 8 verse 28, where the Apostle Paul wrote,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
a90c8319-577c-4610-96c7-ab4ae2c872dc	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	5	288	295	and we know that for those who love God, all things work together for good, for those who are called, according to his purpose.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
5a4b029e-b39e-4e76-8e43-314f4fc33372	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	6	295	299	And here's today's challenge. Have you been interrupted lately?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
b5b7316d-0ae1-4f85-90f5-54af15dca489	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	7	300	303	Has God close the door that you were prepared to walk through?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
78dbd0e3-343b-4730-afa7-7ca3cb621962	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	8	303	305	Trust that it is no accident.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
1ffdfdf7-bf81-4dba-b2c9-725868ca68f7	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	9	306	310	God has promised to direct your steps and his plans are always best.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
e5a3c586-7935-4667-9bb2-1b8ca428e421	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	10	311	313	Hey, thanks again for joining me for today's episode.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
1e896690-244d-458a-97f8-d058a519d1ad	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	11	314	316	I hope you have a wonderful day.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
c341ae3b-74ec-4e75-9b76-8ab7f2cc4de5	7332110b-0ccc-43f9-bc1f-34e4c921d4ac	12	316	321	And until next time, let's continue on our journey as followers of Jesus.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:19.469325+00
4b03db4f-5be7-4a41-9f9f-d57057db1d14	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	0	7	9	Yo yo	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
59cddddc-d0d7-4fb8-a11e-3cdc9e6f4a2e	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	1	9	14	Yo, I hope this message finds you well	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
bbe63e57-6665-4703-bb05-932f1fa367f6	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	2	16	21	However you found it however landed across your screen if you're listening	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
2fbe8f85-a2d7-441d-997e-b01228dccdf1	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	3	21	23	I definitely appreciate it	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
917b0e60-ac76-4abe-beda-b396d5e0e574	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	4	23	29	Sometimes it's all we need just listen in there, you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
a9cc328a-44ce-4f01-9c8d-4be7f77afc8a	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	5	31	33	For my my name is me a lot	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
cca49d26-e3ce-4fea-b2dc-037ead9a1f8d	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	6	33	39	M.E. L.E. to sometimes I go about a guy to meet a guy I'm see	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
dbf3afd3-5fb5-4f6c-a94f-98a624e8fd3f	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	7	40	43	At the time some your brother you love	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
24806e1d-4e54-4102-91de-3e4ff3cea6ae	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	8	45	46	All the above you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
6916a3cc-f8cb-41ec-aead-4f07548a5568	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	9	48	52	Love one and that's what I intend to do, you know, spread some love to you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
ad660616-1078-47f7-a828-c0bf1ec603de	0b8f3cf5-b0d2-47cf-877b-ff4d9998b71a	10	53	56	You know, hopefully it comes back to me, but	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
0c8442b9-9154-411b-9c72-cba505edc085	23075003-e37a-4b81-ad14-4e57c96ced61	0	56	60	Even if it doesn't you know the love was free	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
00ac36ab-6660-4405-96a4-d0936ba893ba	23075003-e37a-4b81-ad14-4e57c96ced61	1	61	66	Yeah, I'll be trying to wrap, but you know me and definitely want to just come in today. It's just	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
871052a2-9890-4503-bfdd-b0cba31bbbff	23075003-e37a-4b81-ad14-4e57c96ced61	2	66	67	a little	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
3e5cbbc7-f068-47b0-9940-48714a9c31d9	23075003-e37a-4b81-ad14-4e57c96ced61	3	68	70	I don't even have anything to offer for M.E.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
99e858d9-d453-456e-a8c9-d03e959d9b41	23075003-e37a-4b81-ad14-4e57c96ced61	4	70	72	But because of my testimony	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
0148446e-c1a2-44ff-8141-bebc69c41deb	23075003-e37a-4b81-ad14-4e57c96ced61	5	73	74	If I'm honest with you all, you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
e3f8e119-7dc6-4e63-9451-654589f42e00	23075003-e37a-4b81-ad14-4e57c96ced61	6	76	80	It's been a while since I've officially like talked about something and been	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
5471dbd0-50ce-4830-9788-1f94f257fb2d	23075003-e37a-4b81-ad14-4e57c96ced61	7	82	87	Present if I'm honest, you know, I'm saying like the last year of my life has been the most	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
50e94ee7-154d-48c9-b162-c1fb6e4cd50c	d306ff91-3f61-4821-b0f3-4f0ee8ced382	0	87	91	Up and down year of my life never if I'm honest, but that's just thus far	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
922441dc-1403-4d73-ae45-ecb8fb217546	d306ff91-3f61-4821-b0f3-4f0ee8ced382	1	91	97	She like that, but right now I'm in a position in reminiscent of like 2020 bro	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
1350d0f4-1833-41a6-960f-27ae1c9b2dda	d306ff91-3f61-4821-b0f3-4f0ee8ced382	2	97	102	Like it feels exactly like I'm in the exact same space as I was at that point	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
124159d9-fe6f-489e-b71a-b0e1dd9dbb09	d306ff91-3f61-4821-b0f3-4f0ee8ced382	3	102	107	You know at that point I was just got laid off of a job and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
15d54129-3865-4a85-9cbd-ff26e0736a98	05562109-70d0-47ae-8398-094a122b83d8	0	109	113	Yeah, it was pandemic bro. I wanted to create. I wanted to do video and stuff like that	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
eacbe5f4-4e99-4096-9469-009ff9644f2c	05562109-70d0-47ae-8398-094a122b83d8	1	114	119	And I started doing it and you know real life happens reality kicks in where it's like all right	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
151f6c59-96d7-47ff-9a66-f5503c176624	05562109-70d0-47ae-8398-094a122b83d8	2	119	122	Yeah, you can make a video to get seen by like	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
af6d6f2e-4e27-4c7d-948b-33d98854a60a	05562109-70d0-47ae-8398-094a122b83d8	3	122	124	2025 people	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
f985b480-dbf8-4417-879d-37859c4cd5b7	05562109-70d0-47ae-8398-094a122b83d8	4	124	126	Get your ass to work	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
7f0c1d88-e469-4158-b487-4db6afdb5ce2	05562109-70d0-47ae-8398-094a122b83d8	5	126	131	So that's what I did. I went to work. You know saying I started working at the ABC store to look a store	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
add0693d-3fb9-4908-a154-43eb1a26dcc2	05562109-70d0-47ae-8398-094a122b83d8	6	131	135	Shout out to anybody at frequency there and you know for all the spirit	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
6dcf93d7-3d80-4290-8709-5f0fd80776bb	05562109-70d0-47ae-8398-094a122b83d8	7	136	142	Needs and shit like that. Yeah, shortly after you know saying I was doing a morning show and all that I do and everything all together	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
37900772-9722-47a0-844a-9614af1cdc53	05562109-70d0-47ae-8398-094a122b83d8	8	142	144	It burnt myself out	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
458205da-b760-416d-a139-2eb7cc64f22b	05562109-70d0-47ae-8398-094a122b83d8	9	145	151	But like the beginning of 2021 and at that point, you know, it was like all right. I was tired of	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
8ba2796a-8e41-413d-a1a6-57d0657ff57b	05562109-70d0-47ae-8398-094a122b83d8	10	152	156	Working at the ABC store because it was like fam. You know, yeah, I'm getting a little bit of money	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
08966903-b8a4-4cbb-b00d-a5f2230cab81	d297f086-1cec-4531-8885-e12cf9bbfd47	0	156	161	But it's not let me be able to do what I want to do and that was the content so I went over to	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
4133e972-21d3-44a5-92ab-8fe30ddc2e59	d297f086-1cec-4531-8885-e12cf9bbfd47	1	162	167	I only said went over like a job at a platform for like a year before hit hit me up	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
fe262066-2d7a-4c3b-8415-fe457676b772	d297f086-1cec-4531-8885-e12cf9bbfd47	2	167	171	So I was like all right cool, you know since better money career path all that shit	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
7b4e596f-b309-44c2-a783-c056308b0d88	a38c3a4a-b753-4327-8d03-2911e3cf9d65	0	172	176	Did that feel like a year some change and you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
83918009-f257-480b-868f-e4369b0c0e00	a38c3a4a-b753-4327-8d03-2911e3cf9d65	1	177	177	Yeah	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
380f381a-c836-4c2a-9dda-ec9461ff1841	a38c3a4a-b753-4327-8d03-2911e3cf9d65	2	178	183	Back to where I started you know, I mean now out digging to that story little later just now that	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
b4a7ad3e-e871-4f09-8e0d-cf93ee3b6ddb	a38c3a4a-b753-4327-8d03-2911e3cf9d65	3	184	188	Sometimes the writing is on the wall and we choose the ignore it	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
975e580b-d98e-4f0a-9323-4fdb786366d2	a38c3a4a-b753-4327-8d03-2911e3cf9d65	4	190	195	But yeah, that's all not the top before another day, but yeah, man in the missed the wall it is like this is then the lowest	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
83a1dca6-89db-4ed9-a892-e44e32737b0d	6d87af8b-a11c-43cb-9a1f-b5c60aa0800d	0	195	197	I've been in a very long time when I say low	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
bb991975-284c-411f-8c39-4662547f01a6	6d87af8b-a11c-43cb-9a1f-b5c60aa0800d	1	197	204	I don't just mean emotionally and nothing like I mean just like being out of the way like just not being seen	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
27a0003d-2579-42bb-9aff-66e474fb9e6e	6d87af8b-a11c-43cb-9a1f-b5c60aa0800d	2	204	208	Not one to be on social media and I want to be heard from like to my friends	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
6999cc01-9e6b-49e0-b2ed-68efd20af8b9	6d87af8b-a11c-43cb-9a1f-b5c60aa0800d	3	209	214	If there's anybody that considers me a friend or anything like that and I gave you the quote shoulder over the last	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
83377f92-b01d-40f3-a462-6215bb598250	6d87af8b-a11c-43cb-9a1f-b5c60aa0800d	4	215	218	Two years you're in half whatever	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
ca9ecd01-cf8d-43d9-85e3-8c40d82a36e0	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	24	463	464	And I appreciate you for listening	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
6ec7a2b2-b669-4f16-a4d4-8b5f258865c4	6d87af8b-a11c-43cb-9a1f-b5c60aa0800d	5	218	224	I said a lot of my play if I'm honest and me trying to be the communicator that I am now like	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
28e012f0-0b49-45c2-8d87-3c5a2197a794	6d87af8b-a11c-43cb-9a1f-b5c60aa0800d	6	225	231	I should have said something so I do apologize as a friend to all of my friends	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
ef78fd4e-177b-4ad3-8cb9-79a63a5cacb1	53cf9e31-3e2d-40da-8897-c9365f9cb0be	0	231	235	But also on that side of that you know saying like I said I was I vowed bro	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
7191275c-cb45-4b35-9758-3d7ab59d9b8f	53cf9e31-3e2d-40da-8897-c9365f9cb0be	1	235	237	I vowed to myself to shut the fuck up forever	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
3339ed27-e6ba-4a98-9176-bab00584069b	53cf9e31-3e2d-40da-8897-c9365f9cb0be	2	238	246	Part of it had to be because I was disgruntled, you know with the process and life and frustrations and shit like that	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
1c14baab-790e-4585-b2d2-2b31bc67e667	53cf9e31-3e2d-40da-8897-c9365f9cb0be	3	246	248	But another part of it was	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
ade146f2-9f5a-46b2-b6ea-2c70d8b395cb	e28be72f-f6e0-489b-b6d9-ee7c8d45e244	0	249	254	Me not believing in myself me not believing in my own dreams and shit like that and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
736ca2ff-93d6-4326-9b87-f3c157ed499a	e28be72f-f6e0-489b-b6d9-ee7c8d45e244	1	257	262	It's tough. This is this is what I will say it's tough when the people around you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
64208c10-9a4c-42a9-9226-f04a0563aa6b	e28be72f-f6e0-489b-b6d9-ee7c8d45e244	2	263	269	See the potential and you more than you see it in yourself or they see the greatness more than you'll see it in yourself	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
ef5fd9bc-ed46-48d0-88ae-d9be056b503d	bd3427cc-5db6-4715-a282-830c1e0a459a	0	269	272	And it's tough to even try to muster up the courage to	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
6d77cd9e-1062-482f-b449-92ed82c1e0d4	bd3427cc-5db6-4715-a282-830c1e0a459a	1	273	278	Try to go after that because for me man for a long time like I said	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
f1f0c211-7624-42ea-a64a-455d4f617773	bd3427cc-5db6-4715-a282-830c1e0a459a	2	279	285	Especially after taking on that career job and it lasted longer than I expected it to and I stopped for	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
7a7426a9-7024-413f-900c-9ef2d693274f	d45a38fa-d421-4737-91cb-a891b1cf555e	0	285	289	Coording and things like that like I honestly thought that was my life at the point I thought I was going to	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
f077251b-c3a8-4e75-ba09-15ac3d2a4d16	d45a38fa-d421-4737-91cb-a891b1cf555e	1	290	294	You know I thought I gave up when the dream and I even thought I gave up when the dream	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
a47414cc-a154-4295-8400-ba2bc27ff39c	d45a38fa-d421-4737-91cb-a891b1cf555e	2	294	298	I I've given up on the dream a few times so for me to even be back here right now	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
4c5e147f-6917-4923-87f6-c4660631fb53	d45a38fa-d421-4737-91cb-a891b1cf555e	3	299	301	Boy it took a lot	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
9c482223-868d-47b5-b7ab-9bbff55d21ce	d45a38fa-d421-4737-91cb-a891b1cf555e	4	303	306	But I say that to say this I	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
75463704-b00c-476a-9446-c734746e74b6	d45a38fa-d421-4737-91cb-a891b1cf555e	5	306	311	Was the video today about where we are in our lives and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
214f7629-cf21-4504-b0e7-5b3f11d47395	d45a38fa-d421-4737-91cb-a891b1cf555e	6	312	319	Oftentimes what we do we all the times are in a place in our lives where	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
f5f96394-8ca4-4a09-92d0-0875a0e547be	d45a38fa-d421-4737-91cb-a891b1cf555e	7	320	325	Two years ago six months ago two days ago we prayed to be in this position now that we're in this position	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
e7ea3273-5a42-474e-8f73-06eb1697dc7f	d45a38fa-d421-4737-91cb-a891b1cf555e	8	325	330	We want to be in a better position. We want to be in a position of more what we're not taking	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
3875b5f8-63b3-417c-898f-4815d505e166	d45a38fa-d421-4737-91cb-a891b1cf555e	9	330	332	a chance to truly appreciate	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
be008896-bfa6-4ae0-b9af-361f389e2835	d45a38fa-d421-4737-91cb-a891b1cf555e	10	333	335	How far we've came in	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
09eb163b-abbb-4653-95e4-9ea260a53518	d45a38fa-d421-4737-91cb-a891b1cf555e	11	335	340	Things we've been doing because for myself if I look back that is my one thing I'm proud of	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
dc5662d4-5dea-4b84-96d9-218358a3e124	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	0	340	342	I'm not the same person I was	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
fe7c83c8-1f89-4b1e-ab5e-db74e18354cc	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	1	342	349	At 25 not the same person I was at 26 and not the same person I was even when I turned 27 if you months ago like	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
8235c724-7481-414a-a6c8-8b4c71221562	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	2	349	351	I've done a lot of growing	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
4ddce580-88b8-4963-873b-332a2ceebd53	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	3	352	355	Some of it oh my own some of it. I was forced to do	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
ddc7be4e-8989-4756-90b7-6f9e9defe3db	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	4	356	357	You know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
856b96ff-af8f-42e8-b624-e40e0314244b	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	5	357	359	For me	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
f8021db2-aa84-4042-a650-c65b64abda04	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	6	361	363	My whole thing is just about being honest	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
75a0544e-8193-4638-ac95-0663e359fc73	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	7	363	366	Like I know what I want out of this life	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
cd86a173-94dc-4fab-b1aa-5dfab203ff7e	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	8	368	372	Am I gonna get it that is the goal? I would love to get it	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
494187d1-8a6a-4bf1-b8f8-efc3341a6950	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	9	374	375	But you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
04215ad9-9e0f-4c15-a58e-67d791fbf360	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	10	377	386	When they meet and draw love as our actions and how we choose the response	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
9d06cd86-cd04-401e-8e21-8396211cd828	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	11	386	388	So right now in my life	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
12702b28-4bb7-4c10-8ee1-86292914f70d	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	12	389	391	In my space where	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
d5ccc512-2eb0-4cb1-ba6c-0a833034576b	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	13	391	393	I'm choose a happiness	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
7920d858-9132-4604-89d0-155a90fa10c3	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	14	395	396	I'm choosing peace	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
ffeb689a-6cbb-44b6-910e-455651973572	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	15	399	404	So I will say this if it doesn't work out	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
69e1688e-7905-4cfa-9ff4-26a4e5dd9606	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	16	408	415	Not that I tried and not that I was real all of it	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
3319eeb9-5bbd-4ebe-99f2-06a93cac9f8a	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	17	415	423	Really happened and I hope you do the same for yourself that I hope you show up for yourself	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
bc80791a-8198-4739-8f66-8b40b047e6d4	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	18	423	429	Hope you give yourself the grace and love that you so desperately yearn for	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
af96a291-228a-4f70-bac8-7e390a5d1b90	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	19	430	439	And I hope that you are friend to yourself today. I'm not sure exactly	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
e8bdaca0-1da9-46dc-b9a9-a4fe19be8224	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	20	441	442	Where we end up?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
df38a3be-e167-40db-8e6b-c4e0b3805030	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	21	443	446	Where we go from here but I do know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
6402adb8-d6f9-4eff-bbb4-b6aa6f83b77c	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	22	449	451	And the end	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
8bc7d1e5-555f-4053-be2e-2dfa52332f16	6ba8ad2e-5dfc-46d5-b412-17ddf942000c	23	452	459	Love is going when so with that I hope you take something	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:25.865493+00
a6f0dbd6-bcf8-4cf7-8355-bc157e1d7a12	53058727-0b38-4252-a713-7e62dd9097ec	0	7	12	Yeah, yeah, yeah, yeah, good morning good morning good morning. How about everybody out there's having a wonderful start to their day	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
c9aec2f4-242d-48a7-9af4-0b3acffe0346	53058727-0b38-4252-a713-7e62dd9097ec	1	13	17	And if you just seen this on the preview what I thought would up though you know, I mean I ain't seen you on a minute	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
69f5169c-7793-4cf0-bdec-8f569c6fdd28	53058727-0b38-4252-a713-7e62dd9097ec	2	18	20	I don't know what that was, but you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
77bc42e8-f1d2-49ee-aca4-f1d75de6af61	53058727-0b38-4252-a713-7e62dd9097ec	3	20	25	There we go. I've heard so you film me. It has been a while and I appreciate you guys for stopping	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
54820035-eb85-4723-ae93-3c9768832b52	53058727-0b38-4252-a713-7e62dd9097ec	4	25	26	But you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
674df7b0-3fd6-4446-abbe-afb8c7a11e38	53058727-0b38-4252-a713-7e62dd9097ec	5	26	31	Welcome back to the five minute morning show with your host the guy that got in me the God MC's young	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
6353559d-5644-47e1-92fa-7c67f1edd9f1	53058727-0b38-4252-a713-7e62dd9097ec	6	31	36	Let appreciate you all for checking and you know what is this this probably like I got third time talking this year	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
87143b0d-a723-4c26-94ae-f93590d398f3	06063f5e-3182-4c0f-8f43-a79975c88ab7	0	36	40	You know, I hope you guys are having a wonderful year, and if not, you know, we got some time to make it	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
7c98c48b-710b-41a8-983f-f82004fe966b	06063f5e-3182-4c0f-8f43-a79975c88ab7	1	40	46	Where for a while you film me, but today I definitely want to just come in and you know offer a little bit of perspective on	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
eaa02c35-ed63-40a4-a796-831845309ffa	06063f5e-3182-4c0f-8f43-a79975c88ab7	2	47	51	a year into the pandemic and you know talk about what's to come next	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
e2c7de63-d779-46ce-bf46-58b274cda954	06063f5e-3182-4c0f-8f43-a79975c88ab7	3	52	52	Honestly	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
3d1e1751-2686-45df-96ee-33f11d927d44	06063f5e-3182-4c0f-8f43-a79975c88ab7	4	53	58	So with that be episode of playing instrument on eighth my flow today's instrument was provided by the great	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
c7ee33ce-07a3-4e7a-ab95-82bc9415ad5b	06063f5e-3182-4c0f-8f43-a79975c88ab7	5	58	61	Erica Bob do with on and on two reasons that chose this instrument	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
6d474c02-98af-4a1b-ac66-9c62d926e060	06063f5e-3182-4c0f-8f43-a79975c88ab7	6	61	67	The first one is because you know it's a light instrument or something that I could walk to you film me is not a light going	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
557089f8-9157-4418-bac9-bac20533f6d4	06063f5e-3182-4c0f-8f43-a79975c88ab7	7	67	74	No, I could talk my talk we can do I think so the second reason is because I felt like this song is all about	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
7abc6e5b-6c0a-424a-a59b-d91a25780774	559eedd6-e8cd-4d7e-bc6d-c6eaeea9ccf6	0	74	81	Percivering honestly you know I mean regardless was going on in the north my side for keep going like a rolling star	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
03037261-aa38-4fb9-9b40-adaf0f8a686c	559eedd6-e8cd-4d7e-bc6d-c6eaeea9ccf6	1	81	86	So we don't keep on pushing for me and that's all that we've actually been doing	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
e8be020d-b868-40ad-a4ba-19f04af724cf	559eedd6-e8cd-4d7e-bc6d-c6eaeea9ccf6	2	86	90	Since this pandemic has started so you know, I mean being a year into the pandemic	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
066e3a27-b8e2-4561-8e83-1430339366c1	559eedd6-e8cd-4d7e-bc6d-c6eaeea9ccf6	3	90	97	The pandemic has changed a lot for us, you know, I mean almost every aspect of our lives has changed in some form of fashion	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
150549fd-5884-4746-b884-f1bee2ccdd3e	8770672f-41f8-40d9-bcc2-028cba228ec5	0	97	102	You know, whether it was the routine that you normally do hitting the gym late night hit	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
45c05a0d-c07e-4318-a422-13507c987eef	8770672f-41f8-40d9-bcc2-028cba228ec5	1	102	105	Man, they brought me a Walmart trips at the midnight	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
ed0605ba-27ec-4a5b-85f5-4fdd3968cd77	8770672f-41f8-40d9-bcc2-028cba228ec5	2	105	111	But that's a whole not the story. You film me a lot of us lost loved ones a lot of us lost our jobs	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
d2b0c945-b170-4c76-9cf3-1a48abcbce76	8770672f-41f8-40d9-bcc2-028cba228ec5	3	111	113	or had the	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
51f79f94-8970-4d1d-ac16-86adbd6a9f4f	8770672f-41f8-40d9-bcc2-028cba228ec5	4	113	117	lose hours lose just we lost a lot through the process	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
0736c90c-da74-4cd8-a5a1-7239e360dc1c	8770672f-41f8-40d9-bcc2-028cba228ec5	5	118	121	But we also gained a lot through that time, you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
f7599ec9-ee0f-498f-96ba-420d4c365f65	8770672f-41f8-40d9-bcc2-028cba228ec5	6	122	126	And I could speak for myself on this one, you know, I mean I gained a lot of perspective along the way	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
796eb836-8678-44da-8c8d-2e1fdcdd1651	8770672f-41f8-40d9-bcc2-028cba228ec5	7	126	131	Just about where I was going and where I was trying to do especially with the unfoundist up for the whole	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
135b85f5-d474-47bc-9e06-7f6be26e3c4d	8770672f-41f8-40d9-bcc2-028cba228ec5	8	132	135	Branding and things like that and you know, it gave me a lot of perspective	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
95126173-06fd-4819-995d-6029eac547f9	8770672f-41f8-40d9-bcc2-028cba228ec5	9	135	141	It gave me a chance to actually understand why I moved the way I moved in what I'm actually trying to do deep down the side	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
4cfb08b7-151b-410e-9b6e-920a0e9716ce	ae914bb1-1947-4980-8ca8-4247d9235231	0	143	145	Yeah, yeah, man a lot of us you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
665fda8f-7ff6-4db6-ac6c-4b2130b3b08c	ae914bb1-1947-4980-8ca8-4247d9235231	1	146	152	Not that you just make it about me a lot of I'm proud of a lot of people, you know, I'm saying like I seen a lot of	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
c7dfa8ce-7650-4a5e-8ce5-80d1adb843f6	ae914bb1-1947-4980-8ca8-4247d9235231	2	152	155	People step outside of their comfort zone during this day	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
301f3f7c-416b-48eb-8158-f5925e380d89	ae914bb1-1947-4980-8ca8-4247d9235231	3	155	159	Some friends become became painters some people became traders	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
6d5ef907-f91b-4a2e-92c1-754ce22cb6d9	178a8b9b-143d-4b06-a58f-31378d69d80d	0	160	164	Some people got closer to parents some people got closer to just people in general	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
80237a0c-3aae-499d-b053-a8ae2dcdcebe	178a8b9b-143d-4b06-a58f-31378d69d80d	1	164	170	But deep down inside what I've realized throughout this entire thing was a	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
1b69d283-052a-41f1-bc22-ab44d593bf4f	178a8b9b-143d-4b06-a58f-31378d69d80d	2	170	174	lot of us are yearning for connection. That's why we're so heavy on social media. That's why	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
a9e8fd72-76fc-435b-8e67-659009a54061	178a8b9b-143d-4b06-a58f-31378d69d80d	3	175	181	It hurt moments outside got close, you know, I said because this was all we had to connect with each other	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
6668240a-607f-4bf4-809e-d5e849286b8c	178a8b9b-143d-4b06-a58f-31378d69d80d	4	181	184	Whether whether whether it was going to the club whether it was going to your favorite store	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
88b875f0-af03-4c84-899b-10d083129fb5	178a8b9b-143d-4b06-a58f-31378d69d80d	5	184	187	Whatever it was you know, I'm saying it changed the fabric of things	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
a9079a65-0ed6-4251-bd6c-225f3228c0a4	59b2068a-9fba-415f-83cb-3ed087819e4e	0	187	192	But that's leading me to the next point, you know, with the world about to open back up	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
caf8e181-bd8c-47b5-8caf-093343e61d78	59b2068a-9fba-415f-83cb-3ed087819e4e	1	192	196	They calling for it by July 4th. They won everything to be back to them. Hey, that's cool	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
f1f311b0-3aa1-43fd-b709-eeab8b01dc32	59b2068a-9fba-415f-83cb-3ed087819e4e	2	196	199	That means we get a summer, but I do want to save this, you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
ebbb7fa9-a586-4177-ba54-383a60887fa7	59b2068a-9fba-415f-83cb-3ed087819e4e	3	200	201	regardless	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
9135f318-a7b2-459e-994c-12b177b15c0b	59b2068a-9fba-415f-83cb-3ed087819e4e	4	202	205	Yeah, regardless of what goes on this summer	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
059d2fe8-c220-440a-b022-51f4dba02691	93945f60-21e9-44c7-8eb4-82c54e960ee6	0	205	210	I want everybody to actually enjoy themselves and take it all in, you know, I mean like	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
9c48c7f6-9392-4871-80f7-b930b6e83bd8	93945f60-21e9-44c7-8eb4-82c54e960ee6	1	211	217	We seen a year ago, you know, we didn't know exactly what was going on and we do know that this next time	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
ca73325b-35de-4f31-b9d6-dd33e0c93783	93945f60-21e9-44c7-8eb4-82c54e960ee6	2	217	223	You know, it's about to be a little lit out here, you know, but enjoy yourselves be safe and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
662f3bce-8443-49c3-a70a-e310024ba904	93945f60-21e9-44c7-8eb4-82c54e960ee6	3	225	227	As always, man, I appreciate you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
0941bd27-009c-4b96-88dc-6440a9a738e9	93945f60-21e9-44c7-8eb4-82c54e960ee6	4	228	228	Like	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
9e39ef5e-a54e-4fc6-b240-d5d0ff179102	93945f60-21e9-44c7-8eb4-82c54e960ee6	5	229	235	Honestly, I just I just lost all a change of thought, but I do have something I do want to save before I go	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
9e023fa7-c6c3-47f9-9373-8fa66521c67e	93945f60-21e9-44c7-8eb4-82c54e960ee6	6	236	242	Instead of giving you guys quotes. I mean, just be awesome game that I picked up alone in the way and I've been picking up a lot of game alone in the way	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
697984e6-faaa-422a-bbd7-10de25e975de	93945f60-21e9-44c7-8eb4-82c54e960ee6	7	242	244	So just be awesome that picked up last night	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
33a8835e-7782-436f-96e9-ea1f4c42e37e	93945f60-21e9-44c7-8eb4-82c54e960ee6	8	245	247	Here we go	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
6796128b-2b04-4ef5-9931-327ad01cb3ab	93945f60-21e9-44c7-8eb4-82c54e960ee6	9	247	252	The only time success comes before it work is in the dictionary	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
6fdcdf1f-7b2e-4b66-b388-9c6aa9f90d52	93945f60-21e9-44c7-8eb4-82c54e960ee6	10	252	255	So let's get to work you film me and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
4f71a117-7aea-40ed-8850-c7296569f3b5	93945f60-21e9-44c7-8eb4-82c54e960ee6	11	255	262	You know me, I appreciate your efforts. I've been by now. I wanted to hear my voice see my face. I look good things like that and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
d603d5d8-3792-4a11-90ec-87a904abddf0	93945f60-21e9-44c7-8eb4-82c54e960ee6	12	263	269	Be smooth. This was the guy. This was what for 30. Peace. I see you out the next time	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:29.53171+00
017647cc-13d0-4c85-a6c4-762cebb8baa4	3a3c6b5c-1718-4eab-8d89-93bf5cd73b98	0	3	4	Yo	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
00cccceb-60ed-47c1-a89a-2cbdea54c05c	3a3c6b5c-1718-4eab-8d89-93bf5cd73b98	1	5	11	Yo, it's been a minute, but we back up Benny you know I mean appreciate y'all for stopping by you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
dab9c78f-6f0a-455c-9d6e-319b42279651	3a3c6b5c-1718-4eab-8d89-93bf5cd73b98	2	11	17	For me welcome back to the five minute morning show with your host the guy the guy in me the guy MC	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
d2698c74-1880-4e72-8a7b-6a19fc796ef8	3a3c6b5c-1718-4eab-8d89-93bf5cd73b98	3	17	21	Shung my luck. You know, hey, just want to start off by saying happy new year	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
83826b2d-a397-47ca-a49c-886e3ab1b8af	4f482f02-e3dd-4b98-9853-f5b1ab0ad8f5	0	22	25	No, it's been a minute since I've seen you guys, but you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
844c03e0-377a-4783-ae05-5a68f14c6d29	4f482f02-e3dd-4b98-9853-f5b1ab0ad8f5	1	26	29	Just want to come and tell you guys where I've been in it's all for a little bit of perspective	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
fe374eb2-b43b-4769-a303-417d643e8875	4f482f02-e3dd-4b98-9853-f5b1ab0ad8f5	2	29	31	I'm gonna need your entire file today and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
8da900c5-7de8-47cd-92e1-bd50fbe01f31	4f482f02-e3dd-4b98-9853-f5b1ab0ad8f5	3	33	38	Let's hop right into you know, I mean with every episode. I play an instrument on to meet my flows today's instrument to	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
15f02729-c03b-4156-8200-35c87ac0f070	5eaff0ce-cf4a-45f0-bd0b-17109af5def3	0	38	40	We've provided by JD kids with all for the love	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
26229f92-cb2f-4232-a236-0d5ed5779d0c	5eaff0ce-cf4a-45f0-bd0b-17109af5def3	1	41	45	You know the reason I chose this instrument was because it's a classic, you know, and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
64a384f2-2c06-40d5-9752-4b0e8852737b	5eaff0ce-cf4a-45f0-bd0b-17109af5def3	2	45	49	The reason is because we're doing this all for the love	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
63fb281c-f086-4642-b38a-47cdaca57a63	5eaff0ce-cf4a-45f0-bd0b-17109af5def3	3	51	56	Yeah, just hop right into it. I guess you know me where I've been I've just been on a journey with myself	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
b5b6aa53-c8d4-42a2-b130-919aad7024ae	5eaff0ce-cf4a-45f0-bd0b-17109af5def3	4	56	60	Just trying to figure out where I'm going the direction that I want to go into and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
45fe3a8a-49c1-4c95-9ea9-91a703097830	5eaff0ce-cf4a-45f0-bd0b-17109af5def3	5	60	63	And actually just trying to figure out who I want to be and things like that	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
e97850f9-3f52-4355-b182-829ca17a100d	5eaff0ce-cf4a-45f0-bd0b-17109af5def3	6	63	70	So, you know, you just need to take some time myself off of myself the perspective give myself a chance to actually breathe and actually	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
035e4026-fd50-4fb8-9cdc-0395240a008f	ff11d509-6549-4a1d-b3e3-f3f22e9f35b5	0	71	74	Get the answers, you know instead of trying to rush through things	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
4e3951c3-39d0-4d80-88a6-96fd3cc96d13	ff11d509-6549-4a1d-b3e3-f3f22e9f35b5	1	74	77	So that's what I've been doing, you know, I'm still on that journey	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
64254d16-7441-4133-90d1-059eb9b52fec	ff11d509-6549-4a1d-b3e3-f3f22e9f35b5	2	77	83	So you guys might not hear from me as often or like the last little break you might not hear from me at all	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
1eec3a7b-2cac-46cf-a4cc-9f07c29fe7eb	ff11d509-6549-4a1d-b3e3-f3f22e9f35b5	3	83	89	So that's that, but I definitely wanted to come in here today and offer this piece because	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
87531a83-66a1-4a9e-a32f-d0d5830654f1	ff11d509-6549-4a1d-b3e3-f3f22e9f35b5	4	89	94	Somebody might need to hear it and that is just the trusty self, you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
afa0ff13-2059-4823-b1df-7f947d6c990a	ff11d509-6549-4a1d-b3e3-f3f22e9f35b5	5	94	101	You have your best interest at heart and sometimes we don't make the best decisions and things like that	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
bb59a35a-7a14-4706-b707-1a255e9ec493	ff11d509-6549-4a1d-b3e3-f3f22e9f35b5	6	101	108	But you know, there's something to gain from actually the power of making your own decisions and the power of	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
ed380161-148e-4203-a212-70bcfabc931c	def7bf6f-1f86-4a7d-b314-1aa8f09798ee	0	108	112	choosing to live in your own life and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
77ff01f1-8d29-4645-8057-66da48b9d2b8	def7bf6f-1f86-4a7d-b314-1aa8f09798ee	1	113	119	That's where I've been at you know trust them myself learning how to trust myself and it all starts with	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
60298d7b-1e7f-48b9-bf83-859491fb7bcd	def7bf6f-1f86-4a7d-b314-1aa8f09798ee	2	119	124	You know being aware of who you are being honest with yourself and actually putting in the work	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
582a85f5-f519-4189-afa4-0a2225729429	def7bf6f-1f86-4a7d-b314-1aa8f09798ee	3	125	131	So, you know, I'm not going to need you in time today like I said all I wanted to come in today and say	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
bc9d9d2d-a8a3-49a6-add6-e1cf7eae324d	d92b3fef-2f38-4ede-96ad-77deff28010c	0	131	139	It's just trust yourself. Give yourself a chance to actually achieve what it is you say you want to do and you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
096ccf16-9e98-47f8-8aef-528b59c2dce5	d92b3fef-2f38-4ede-96ad-77deff28010c	1	140	144	All right, we can get there. I appreciate you guys as always	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
e593e852-4c93-4102-ae6e-9b75e3434a36	d92b3fef-2f38-4ede-96ad-77deff28010c	2	144	149	I mean, I see me. I'm trying to put some kind of air in my life. You feel me trying to feel good about myself	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
5c8ebbf6-4164-494d-b380-83f7a8705b53	d92b3fef-2f38-4ede-96ad-77deff28010c	3	149	153	I've already can't see my blue lights, but they throw you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
f556d205-8c63-4dab-a5a9-651cc8f35305	d92b3fef-2f38-4ede-96ad-77deff28010c	4	153	155	God knows in the back, I got to you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
e3834f7b-ff52-406d-8d13-549bf77df4bc	d92b3fef-2f38-4ede-96ad-77deff28010c	5	155	159	I'm trying to tell you that I found it logo and we here so	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
04ac985f-6a66-47cd-88ac-d112e9d7d3bb	d92b3fef-2f38-4ede-96ad-77deff28010c	6	159	165	Appreciate your eyes always be smooth be happy enjoy your mouth because you know it's black history	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
101a1ebc-85a0-4d42-ba49-709aa5172a3c	d92b3fef-2f38-4ede-96ad-77deff28010c	7	165	167	You know wake up	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
befbbf01-ad09-4f6a-aba3-00db9d14909f	d92b3fef-2f38-4ede-96ad-77deff28010c	8	167	170	It's the first time I appreciate your eyes be smooth	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:32.774999+00
23b9216b-5a2f-4d29-9239-bfefc51d2f88	74b3f23d-3edb-4102-be3c-094abcfe129b	0	12	17	Hey, hey, everyone. Welcome back to another episode of the Michael podcast on podcasting.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
9549fdd6-fcdd-4d3f-8dad-8927c4fce33b	74b3f23d-3edb-4102-be3c-094abcfe129b	1	17	22	I am your host, expert authority, business coach and podcast expert, Christine Blasdale.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
9cf0eb9b-7872-41a4-95aa-b147ab11b1cc	74b3f23d-3edb-4102-be3c-094abcfe129b	2	23	29	And it's been a while. I apologize. It's been quite a while since I've posted a new episode, but I've been busy.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
0afa3894-e681-4fdc-8c6f-700a9cf2efd3	74b3f23d-3edb-4102-be3c-094abcfe129b	3	30	35	I've been very busy and part of that is because I have just released.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
6c7693fa-6a47-4881-9bf3-9a5255b72296	74b3f23d-3edb-4102-be3c-094abcfe129b	4	35	43	Oh, I took some time to write my brand new book called Podcast Dynamics, unlocking the secrets of profitable podcasting for beginners.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
0b41c923-c3be-425a-b080-26a39331cbf8	74b3f23d-3edb-4102-be3c-094abcfe129b	5	44	47	And it has been a project of love.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
0fa4f44c-df46-48c4-8993-5810b447a457	74b3f23d-3edb-4102-be3c-094abcfe129b	6	48	53	I've just poured my heart and soul into this book. Again, it is for beginners.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
b80f4532-6f3e-4fbd-873e-d8f73cb2b92a	74b3f23d-3edb-4102-be3c-094abcfe129b	7	53	63	And it is not just about the current situation with podcasting and how you can use a podcast to promote your business and use it as a marketing tool.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
19c2e06e-1220-4a55-a68c-a9ca49fc8440	7e1a0421-5613-4d3b-9edd-c3f24c63a221	0	63	74	But it's also about the future of podcasting and incorporating everything from chatGPT, AI technology, all of the great AI tools that you can use.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
b583b3f9-2661-4482-b8f9-26b238bfbc9f	7e1a0421-5613-4d3b-9edd-c3f24c63a221	1	74	82	But also what the future looks like when we are thinking about podcasts and podcast, which is the video version.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
4b05556c-6691-4540-88de-21688988bbb5	7e1a0421-5613-4d3b-9edd-c3f24c63a221	2	82	91	I believe it's going to be a lot more interactive. I believe that your audience, your subscribers are going to have more of an interactive role with you.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
74e8e408-92a6-429a-8a58-bb2e88a1beeb	dc9120ec-bf89-4697-ab55-07d48c6a74f4	0	91	94	And I'm just super excited about about the book.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
523c9248-95ff-471f-901c-34ff9dc334f9	dc9120ec-bf89-4697-ab55-07d48c6a74f4	1	95	98	And so today's episode is going to be talking about podcast economics.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
9f8084c3-7405-4654-bb19-b78c122152cf	dc9120ec-bf89-4697-ab55-07d48c6a74f4	2	99	106	And if you'd like to get your copy, you can get the paperback version or you can get the Kindle ebook version as well.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
c4f7cbe3-cafe-42ff-a83c-4865cd85e8c2	dc9120ec-bf89-4697-ab55-07d48c6a74f4	3	106	108	On Amazon, it is out now.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
2b5d5d75-9cc9-48a7-b220-3f84f0661fcd	dc9120ec-bf89-4697-ab55-07d48c6a74f4	4	109	112	And both additions are available for you to purchase.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
02a3c3fe-6663-4fc1-a8a0-199c4145d0c1	dc9120ec-bf89-4697-ab55-07d48c6a74f4	5	112	119	And if you're interested, the paperback is 2495, US, and the Kindle is 299.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
de779c5d-70df-4c1d-a78d-658157f7ea79	dc9120ec-bf89-4697-ab55-07d48c6a74f4	6	119	125	The great thing about the Kindle version is that you can actually click on all those links that I have.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
58d7301d-d014-403f-9656-05970143313e	dc9120ec-bf89-4697-ab55-07d48c6a74f4	7	125	130	I have links to different suggested microphones, different software that I use.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
f94c806b-7a55-431d-b2c7-2967b6a47ec9	86d31a83-6f1c-420d-a29b-f10be67a427a	0	130	137	So it's really a wonderful way to get resources and to access those resources right away.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
39355ee1-4198-4e3e-8de3-083ddae5d009	86d31a83-6f1c-420d-a29b-f10be67a427a	1	138	145	So I'm going to just take a real quick gander through this book that I'm, again, I'm so excited about this.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
364480f0-112e-454c-92ad-98d4546cb1ec	86d31a83-6f1c-420d-a29b-f10be67a427a	2	145	149	And I wanted you to be the first to know about it because, well, you're my beautiful audience.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
a16d420d-a012-47e9-8835-1b09fb9f75ca	eb9db050-7226-4f62-b1f6-7b4c62b846ad	0	150	152	And you need to know what I've been doing.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
b7226bfc-98b1-4c50-b123-e625d3e1619d	eb9db050-7226-4f62-b1f6-7b4c62b846ad	1	153	155	So just in some of the table of contents, the different chapters.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
f47f271d-5024-41d5-bf92-b62ea681082c	eb9db050-7226-4f62-b1f6-7b4c62b846ad	2	156	158	Yes, podcasting is still the new gold rush.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
502e70ee-2be7-45f6-8af3-6e580c1b4d2f	eb9db050-7226-4f62-b1f6-7b4c62b846ad	3	159	160	And now is the time to get in.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
dd719931-119d-4cc0-ad7d-ef366691a66c	eb9db050-7226-4f62-b1f6-7b4c62b846ad	4	161	162	That's chapter one.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
d1aece3f-8a17-4293-b236-e0063881277b	eb9db050-7226-4f62-b1f6-7b4c62b846ad	5	162	166	The chapter two is the popularity of podcasts keep growing.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
71fcbaeb-5fcc-40a3-9b41-b858a4723f9b	eb9db050-7226-4f62-b1f6-7b4c62b846ad	6	167	171	And chapter three is how to promote your own business with a podcast.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
72d213a9-fe56-4509-94ed-6b0420fd0468	eb9db050-7226-4f62-b1f6-7b4c62b846ad	7	171	180	That's one of my favorite chapters because it's about how you can no matter what your industry is or what your business is, how you can use a podcast to promote your business.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
166ae53b-ab75-440c-a73f-01d9827bdab4	231cfd16-7cdc-41cc-b341-93e8701ae698	0	181	182	It goes on.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
4722715d-a5c3-4297-b84a-9920d427d96b	231cfd16-7cdc-41cc-b341-93e8701ae698	1	182	185	We've gone to how you can promote your business as a podcast guest.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
6c984eca-ad64-4812-8ccc-b0c17b43b980	231cfd16-7cdc-41cc-b341-93e8701ae698	2	186	188	I've been on many podcasts shows myself.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
8337e953-99dc-4610-8488-8a1a997bdc00	231cfd16-7cdc-41cc-b341-93e8701ae698	3	188	191	Yes, you can also be a guest on podcast shows.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
f8cf6e69-be9b-4c2f-93a7-6315d53ff068	231cfd16-7cdc-41cc-b341-93e8701ae698	4	192	197	And I love helping my clients get booked on different programs, radio, talk shows, all that stuff.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
446e20e1-1c1a-4494-a0dd-41bc5627d6f5	231cfd16-7cdc-41cc-b341-93e8701ae698	5	197	200	How you can establish your expert authority with a podcast.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
f2ff5f00-ab85-44bc-983a-2dae26494b00	231cfd16-7cdc-41cc-b341-93e8701ae698	6	201	207	It's really important showcase your wisdom showcase your specialty your area of expertise.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
e569a979-539b-4dba-b3dc-9f63fac7f7e6	231cfd16-7cdc-41cc-b341-93e8701ae698	7	208	214	Let your podcast be your platform where you let other people know what it is that you do and how you can help them.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
83f9d4da-fb0e-4ba7-bba7-2cd714a1c558	231cfd16-7cdc-41cc-b341-93e8701ae698	8	215	218	You can use your podcast to meet notable authors creators and dream guests.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
8690140a-799e-40fd-b347-096575804cf7	231cfd16-7cdc-41cc-b341-93e8701ae698	9	219	222	I have met so many amazing people with my podcasts.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
fa1044c5-eec0-414d-a458-2364581c2305	231cfd16-7cdc-41cc-b341-93e8701ae698	10	222	226	I have two currently right now and I'm developing a third podcast.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
5f822dc9-18bf-454b-8d57-3c077a15af1f	e0da7891-30cc-4e3e-a092-ff5167c47b71	0	226	230	And once that gets launched, I will let you know.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
1c1f6e3b-000e-467b-8b16-c9068363e825	e0da7891-30cc-4e3e-a092-ff5167c47b71	1	231	233	But this this book is just it's full of information.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
fe55420a-c3b9-4e7d-8804-fca38b67b8b9	e0da7891-30cc-4e3e-a092-ff5167c47b71	2	234	236	How you can use your podcast to help others.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
d95547bd-2fc8-4ef2-991f-c1948ce624dd	e0da7891-30cc-4e3e-a092-ff5167c47b71	3	236	239	How you can create income from your podcasts.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
83836ee4-a323-43f7-9891-cab0d2410736	e0da7891-30cc-4e3e-a092-ff5167c47b71	4	240	244	And then we jump into the future of podcasting.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
8bf0a4c1-7895-46ac-88cf-86f5cfe1544d	e0da7891-30cc-4e3e-a092-ff5167c47b71	5	245	249	I also give you some hot tips on how to record in zoom for your video version of your podcast.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
d50c0401-9cc1-430f-91d0-1f06e600ba28	102eb6c8-62a9-4b10-8090-c6ba859e0222	0	251	252	Some sneaky little tips and tricks.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
e27649fa-4cdf-455b-a81d-9b439a78eaf9	102eb6c8-62a9-4b10-8090-c6ba859e0222	1	252	254	It's all included in the book.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
f8f134e1-53d2-494e-bdde-9305b6c5e107	102eb6c8-62a9-4b10-8090-c6ba859e0222	2	254	257	And I would love to see your review.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
ba146199-17a5-40c6-970b-b20c16bc2202	102eb6c8-62a9-4b10-8090-c6ba859e0222	3	257	260	If you're able to grab a copy, make sure you post your review.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
80e7b0a9-9aee-49d7-a816-739c8ca245a0	102eb6c8-62a9-4b10-8090-c6ba859e0222	4	260	263	But the book is now available at Amazon.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
0f645f35-e3bd-4f47-96c3-3fc38a9ebca0	102eb6c8-62a9-4b10-8090-c6ba859e0222	5	264	267	Again, if you're interested, there's going to be a link in the show notes.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
dafca5e3-91ad-4460-a0ff-c737fffcc3d6	102eb6c8-62a9-4b10-8090-c6ba859e0222	6	267	272	You can just click on it and get either the Kindle version for two dollars and ninety nine cents.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
180f23ae-3984-4636-b881-74471116fd92	102eb6c8-62a9-4b10-8090-c6ba859e0222	7	272	273	What a bargain.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
484c63fe-fc69-4c82-806c-db45785119eb	102eb6c8-62a9-4b10-8090-c6ba859e0222	8	273	274	Or you can get the paper back.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
ce579292-e77c-4ec1-9a38-4e683d32358b	102eb6c8-62a9-4b10-8090-c6ba859e0222	9	274	279	If you're someone who likes to flip the pages over and highlight stuff.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
7661ed49-c007-4a87-976e-36c42a3d1d01	102eb6c8-62a9-4b10-8090-c6ba859e0222	10	279	281	You can get the paper back to 24.95.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
52f08892-be6f-4deb-a065-11c1304b79eb	102eb6c8-62a9-4b10-8090-c6ba859e0222	11	282	282	All right.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
e34daf22-c943-4aae-8b7f-38cb613ba6ed	102eb6c8-62a9-4b10-8090-c6ba859e0222	12	282	284	Make sure you check out the show notes.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
4f030a66-2244-42a8-99e7-87805cd04a4d	102eb6c8-62a9-4b10-8090-c6ba859e0222	13	284	286	And until next time, happy podcast.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:36.167279+00
accd7163-59e1-4d4f-95b9-56c5d7caede6	a4780505-3d89-4c67-aa99-fcee721c3ca1	0	11	17	Welcome back to the micro podcast on podcasting. I am your host Christine Blasdale your expert authority	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
3d080429-5b40-42ae-a8bb-028750e6c4ad	a4780505-3d89-4c67-aa99-fcee721c3ca1	1	17	24	And I'm also a podcast coach for you folks who want to create a podcast in your beginning your journey	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
53ebcad1-ab43-4d61-91b6-240d3cd7163b	a4780505-3d89-4c67-aa99-fcee721c3ca1	2	24	26	Today's very special because in this episode	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
a7162c24-86da-492d-81ad-28865242ef01	a4780505-3d89-4c67-aa99-fcee721c3ca1	3	26	32	We're going to be speaking with Julie Hood who is the creator behind course creators	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
c9a7f156-aa23-4fe2-892d-73270df48781	a4780505-3d89-4c67-aa99-fcee721c3ca1	4	33	38	HQ.com and she's gonna talk about the importance that if you have a podcast	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
a8e55084-ac8a-422e-940d-bf83a0d9e457	a4780505-3d89-4c67-aa99-fcee721c3ca1	5	38	46	Why you want to create a course based on your expertise and promote it in your podcast?	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
6efd4b7e-9b15-4f70-a44d-4681d002d668	a4780505-3d89-4c67-aa99-fcee721c3ca1	6	46	55	Let's listen to what she has to say you can you talk about the importance if someone has created a podcast about the importance of creating a course and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
e2248f26-15dc-4c95-8871-693ad7371e5d	5197e620-0ddc-4bb2-b927-622f0b44c043	0	56	62	About how they can advertise that course in their own podcast	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
c9a11147-1671-42ef-bb04-6ed720e8814e	5197e620-0ddc-4bb2-b927-622f0b44c043	1	64	65	Yes, yes	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
7aa4945e-e3b6-4e62-b245-f3b4f1e13900	5197e620-0ddc-4bb2-b927-622f0b44c043	2	65	77	Right, so I work with a lot of podcasters who have recognized that building up an audience to where they could get to normal advertising rates	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
9992c88b-d56b-43b8-947f-c240ae152080	5197e620-0ddc-4bb2-b927-622f0b44c043	3	77	78	It's gonna take a while	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
3c390583-69d0-4d5b-93b6-9ba7b40dcd8b	5197e620-0ddc-4bb2-b927-622f0b44c043	4	78	83	So instead to have a monetization to your podcast	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
0f3c59a1-68fc-4c42-a9b3-a61b4e192907	5197e620-0ddc-4bb2-b927-622f0b44c043	5	83	89	One of the things I really really love is to use a mini course or a course of your own	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
f9feb12a-dc7a-4356-b08c-59adbf816a98	5197e620-0ddc-4bb2-b927-622f0b44c043	6	89	98	So especially if you have a non-fiction podcast where you're in helping people teaching people instructing people on a certain topic	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
17de2deb-4c66-494e-b5b0-cd8c3f015fae	5197e620-0ddc-4bb2-b927-622f0b44c043	7	98	106	If you can put together a mini course or smaller course and you can sell that then on your podcast	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
065e71f7-b7ea-4111-a49a-7552339fe411	3e766071-0090-4bd9-8eb4-3749cb159b97	0	106	111	And it doesn't have to be complicated or super sailsy. It's just a short little thing	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
7c5fd8c4-a862-4d6e-a84b-c850c739d993	3e766071-0090-4bd9-8eb4-3749cb159b97	1	111	116	Hey, by the way, I've got this mini course. I put together if you want to learn more and you want to know about it	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
099e2149-c2b2-4cfe-a7f0-1f994d28d268	3e766071-0090-4bd9-8eb4-3749cb159b97	2	116	122	Here's the link I'll put it in the show notes. You can click over and if it comes a really good revenue source a four	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
fa6531dc-796d-4719-87cc-e80556c9cf19	3e766071-0090-4bd9-8eb4-3749cb159b97	3	123	129	podcasters that is not a typical one that a lot of people do you but I I've been	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
acf410dc-68a8-4a8d-b254-f8b2dbf1cbd8	f685208e-0981-42da-9263-dfd2651e560c	0	129	133	thrilled with it because I use my podcast all of the time to help connect with my students	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
c5a99d82-0513-4ca3-8cdc-1baae7956f38	f685208e-0981-42da-9263-dfd2651e560c	1	134	138	I would suggest that people also if you have if it's a	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
14d4f088-c006-4a4a-8c7c-85d9d52f1617	f685208e-0981-42da-9263-dfd2651e560c	2	138	145	You know if it's a book if it's a if it's a physical book or a course that is an evergreen	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
e2dd051e-16e6-4873-a503-c7dd092c4115	f685208e-0981-42da-9263-dfd2651e560c	3	145	149	Right, so that if anybody's listening to it in February or January or wherever	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
501fb645-1340-4e06-9e82-038a19824583	f685208e-0981-42da-9263-dfd2651e560c	4	150	158	It doesn't matter but if you if you're able to create in zoom make a 30 to 40 second	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
ca52674c-6b25-420a-8e06-e063d3acf772	f685208e-0981-42da-9263-dfd2651e560c	5	159	164	Recording in zoom with either and showing them you know	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
7d90be41-6e42-4725-86c0-8ff1cc1fa2e8	f685208e-0981-42da-9263-dfd2651e560c	6	164	169	You can get this book or you can get this course any kind of visuals that you can have and it can go	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
8ee7a37c-a83e-470e-a0da-95f86285c54a	aef28f78-8ce3-4a77-80a7-9704b78102a5	0	169	174	You can do that in editing you can actually put the visual of the course the artwork and things	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
06a6f4eb-9db8-4a58-a7f4-5373865beda3	aef28f78-8ce3-4a77-80a7-9704b78102a5	1	174	181	But if you're able to create that in zoom then you have the video version of it and the audio	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
6557ef1c-6e35-4ca2-930e-3fb83089c7ec	aef28f78-8ce3-4a77-80a7-9704b78102a5	2	181	187	So that you can insert it in your podcast, but you can also put it on YouTube with the video version of your podcast	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
905dd888-8198-473d-b6a9-3393575b17ed	aef28f78-8ce3-4a77-80a7-9704b78102a5	3	188	191	I do that right now with just	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
174db629-75ac-4943-b669-edd9427353fa	aef28f78-8ce3-4a77-80a7-9704b78102a5	4	193	195	Announcing my strategy sessions the free strategy sessions	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
7d30eb8a-9d7c-4871-b8db-1ad2702edf78	aef28f78-8ce3-4a77-80a7-9704b78102a5	5	195	201	But I think for products specific it would be very very smart to just put that in there and again	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
dc853ddc-03f7-4121-abae-f8f13c108d9a	24c90231-560d-4cce-a2be-b52473e9d5dd	0	201	204	Don't make it like she was saying don't make it five minutes long	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
340ced04-3ca4-44ba-9be4-2e05a64d739b	24c90231-560d-4cce-a2be-b52473e9d5dd	1	204	209	You know make it like a commercial make it short short and sweet boom	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
8f17bd38-f3da-4b8c-b79a-e6af7955eaa8	24c90231-560d-4cce-a2be-b52473e9d5dd	2	209	211	Right and	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
35250257-ed12-4499-af4f-1eb04d3e8cc3	24c90231-560d-4cce-a2be-b52473e9d5dd	3	211	214	Give yourself plenty of runway. I had a coach once it told me	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
5417af2d-9fae-4982-b3ea-c5b2429b5e42	24c90231-560d-4cce-a2be-b52473e9d5dd	4	214	219	six to eight weeks out from a specific thing you should be starting to talk about it	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
d27416e8-2e09-49b4-af19-1a71b0fc7c04	0a288c49-568a-4d95-87fb-d37316d0dd46	0	219	225	And I remember my mouth kind of dropped because I would do maybe a couple episodes two three episodes and she's like	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
02040d82-7b77-4e71-9f92-e18009de5570	0a288c49-568a-4d95-87fb-d37316d0dd46	1	225	226	Oh no	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
4ff08e26-6d33-471f-9de2-ada50f043e30	0a288c49-568a-4d95-87fb-d37316d0dd46	2	226	233	People need to hear it over and over again. So six to eight weeks ahead so yeah and same thing for your email	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
618ba6da-02f2-42e2-b9a4-9418196436df	0a288c49-568a-4d95-87fb-d37316d0dd46	3	233	238	Blast out as well. You got to remind people and give them and don't do a countdown clock necessarily	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
f8561a39-684d-4162-9a5c-26bb08ddb226	00cac318-a567-4bca-9412-4f1d31b5b26d	0	238	243	You don't have to but you could say you got four days left you got you know 24 hours left those type of things	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
550bce36-86e1-4c11-bf96-93d1fb2c645c	00cac318-a567-4bca-9412-4f1d31b5b26d	1	243	245	People will	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
9cd7c40b-2460-43e1-9550-5b89ba94a909	00cac318-a567-4bca-9412-4f1d31b5b26d	2	246	249	Especially when they are they're reminded that they don't have much time left	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
213f889f-8d03-4e62-965e-bf251f205949	00cac318-a567-4bca-9412-4f1d31b5b26d	3	249	252	They will you know hopefully respond and and get on there	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
9a34758e-01cd-423a-963c-32924d4c420c	00cac318-a567-4bca-9412-4f1d31b5b26d	4	252	258	Julie hood you are amazing absolutely I'm so happy that you joined us today	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
f641ade5-c97f-484d-9586-b7273e33d087	00cac318-a567-4bca-9412-4f1d31b5b26d	5	258	264	Once again that was Julie hood you could find out more information by going to course creators hq.com	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
34f9a59f-d1ed-46f7-a0cf-82f379ccad9c	00cac318-a567-4bca-9412-4f1d31b5b26d	6	264	268	And since this episode is all about using your podcast to promote your courses your books	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
52dc135f-64e5-4952-a671-09a87c219958	00cac318-a567-4bca-9412-4f1d31b5b26d	7	268	274	I wanted to let you know that I have just released on Amazon the Kindle and the paperback version of	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
7c6dcdf1-65af-4b2c-998f-5b99ab6e789a	00cac318-a567-4bca-9412-4f1d31b5b26d	8	274	276	Podcasting for beginners the workbook	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
bdcbf400-2c0b-4eea-a4ea-b71abbc5fcc2	00cac318-a567-4bca-9412-4f1d31b5b26d	9	276	281	It is brand spanking new you can get yours on Amazon. I'll put the link in the show notes	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
70b159ba-97e2-4122-9f77-15f91e5c6af4	00cac318-a567-4bca-9412-4f1d31b5b26d	10	281	288	But check it out. I know you're going to love it. So check it out on Amazon and that's all we have time for today	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
4a95d0ab-c76f-4bad-8f7c-33d6cc1d32cc	00cac318-a567-4bca-9412-4f1d31b5b26d	11	288	295	on the micro podcast on podcasting. Make sure you like subscribe comment as much as you can on this program	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
9e3cf815-c15b-4ee3-9902-335c2015ebcd	00cac318-a567-4bca-9412-4f1d31b5b26d	12	295	299	And if you want to find out more about my coaching my podcast coaching you can go to	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
3e036d30-9234-4b4a-b6d8-cff8d76e17dc	00cac318-a567-4bca-9412-4f1d31b5b26d	13	299	305	Christine Blastale.com. That's Christine Blastale.com and until next time happy podcasting	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:39.58001+00
419c338f-3284-4dac-95d0-93c072434b45	0ff77a0c-bcf4-4dd6-bb10-1a65b21eabab	0	12	16	Welcome back to the five minute micro podcast on podcasting. I'm your host Christine Blasdale	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
d7428525-74f3-422b-8a50-e20b539f19b8	0ff77a0c-bcf4-4dd6-bb10-1a65b21eabab	1	16	20	and I'm excited for today's episode because I am a very special guest	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
3964a578-90bc-4375-9637-7331b58cfffa	0ff77a0c-bcf4-4dd6-bb10-1a65b21eabab	2	20	26	Mr. Joseph Hecker who is an amazing consultant for businesses. He's also a podcaster	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
cce53d99-5033-43e9-9ed1-f83715543da3	0ff77a0c-bcf4-4dd6-bb10-1a65b21eabab	3	26	34	and he's going to be talking about the importance of being a guest on other podcast if you are a podcaster yourself	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
abc9060b-a68f-403b-b55a-c2317fcd08bf	b3e81349-ba49-483d-a50b-b8c9daa8f8a4	0	34	40	This is important. Catch our interview that we did just the other day. I think you're going to dig it and stay too	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
173f9ee6-b6a6-4e22-a62e-be3c7a16d44f	b3e81349-ba49-483d-a50b-b8c9daa8f8a4	1	47	56	think about also doing joint ventures. Join up with someone who you can compliment. One superhero is great.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
bba1a1e0-c351-436a-8cb1-112c1fa92fb3	b3e81349-ba49-483d-a50b-b8c9daa8f8a4	2	56	61	You know Batman alone is awesome. Superman. Yeah, cool. But when you have the, you know,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
5e88bad4-d53d-416c-925c-a9a7e4bbc750	b3e81349-ba49-483d-a50b-b8c9daa8f8a4	3	61	70	the marvel, the team that can come in together, the audience gets something so different than just	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
8dabd687-e334-49ff-a01e-d903ad84d141	6cfb111d-e31d-4e12-91e0-1034938ab22e	0	70	75	you alone. That's right. So that's what I recommend. And I think these co ventures that are happening.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
ed8b6ccb-0ae9-45f8-9a4f-a62a53f67324	6cfb111d-e31d-4e12-91e0-1034938ab22e	1	75	80	I'm doing a lot now. I'm doing workshops and things. And I love it because I can give my	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
5b79894d-a76d-4ef9-b216-15ef832b3f6f	6cfb111d-e31d-4e12-91e0-1034938ab22e	2	80	86	genius. But there's other people that have their genius. And when you put those two together,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
b6dc3fce-e4ce-45d2-8290-8531a60ab858	6cfb111d-e31d-4e12-91e0-1034938ab22e	3	87	93	ooh, you create something so magical. Oh my gosh. I could touch you forever. Oh, yes, we do.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
41bb8607-688f-4c5d-8971-7180ce96e65b	1250558d-015d-4186-9b79-62560bbb3b88	0	93	99	And feeling like we're like, we compete or we stand our lane. And I won't see, I won't say the	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
9b91c4e5-c9da-42db-9fc1-06b49d9d3509	1250558d-015d-4186-9b79-62560bbb3b88	1	99	108	person's name. So when I hand those top design podcasts on, one of the people invited	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
0ddc472f-6ab5-4040-87aa-8f50a005cf9a	1250558d-015d-4186-9b79-62560bbb3b88	2	108	114	called me up beforehand and said, hey, so why would I do that? Like, you know, why would I,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
31395b3a-3d2c-4446-ae96-a6a4295f17c0	1250558d-015d-4186-9b79-62560bbb3b88	3	114	120	why would it be on a podcast with other podcasts and, and I said, oh, well, here.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
519e05bd-c0f0-4eaa-83d7-3938f585dbdc	1250558d-015d-4186-9b79-62560bbb3b88	4	121	127	So Louanne was going to be on the podcast. I was like, hey, we're pull up her Facebook. How many	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
095bb9df-9c82-4a50-b004-36d57c268387	1250558d-015d-4186-9b79-62560bbb3b88	5	127	132	mutual friends do you guys have? And so he looked and he was like, oh man, I only have 98.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
70b211ce-6411-4300-bee1-2bd8c00781f9	1250558d-015d-4186-9b79-62560bbb3b88	6	132	139	And I was like, okay, but her followers listened to her podcast on interior design. Your followers	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
fe042f20-a1ea-45ce-a172-85dc090bc5da	9cbdab12-261f-4b43-895a-ec80dacf5673	0	139	146	listened to your podcast on interior design. Why, why hasn't there been crossover? And he's like,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
8c5043f7-07bb-4417-bd1b-3a89b29ab106	9cbdab12-261f-4b43-895a-ec80dacf5673	1	146	152	I don't know. He's like, I would have thought the number was bigger. We had 100,000 people tune in.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
ce02e894-21df-470e-90bb-f675ec6fde91	9cbdab12-261f-4b43-895a-ec80dacf5673	2	152	156	Again, not my followers. I was, I was brand new. I was nine weeks in.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
28046143-8792-4928-8d00-79ff7fc548f3	9cbdab12-261f-4b43-895a-ec80dacf5673	3	157	162	But it was because I was bringing people together. I feel like the sometimes and a lot of the	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
4e58994c-391a-42b0-968d-9df244e20acc	dd46dff0-f1c4-4d04-95ad-c72af8d0895e	0	162	167	times like Joe Rogan, he brings all these people because, you know, like, people tune in and see who	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
cbeea367-bf74-4c86-84b7-6bb4901a539b	dd46dff0-f1c4-4d04-95ad-c72af8d0895e	1	167	173	he's got next. I caught the Jimmy Fallon effect, too. Jimmy Fallon, I don't even know what he does,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
b4d354ee-11f8-43d5-a4b9-e85e3790934e	dd46dff0-f1c4-4d04-95ad-c72af8d0895e	2	173	178	you know, during the day. I think he's like a schoolteacher. He just lives on set. I don't know,	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
34ca6a97-8bcb-402b-afd0-686eb96cc2ee	dd46dff0-f1c4-4d04-95ad-c72af8d0895e	3	178	183	because you never hear from him the rest of the time. But he seems to know where everybody. And you	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
2a165cf6-2359-4c8d-99af-b7d1a5a2db7e	a85fcee4-204c-4853-9e0e-71962d2b717d	0	183	191	don't really tune in for Jimmy. You tune in for his guest. Lean into the guest part of it. It will	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
59befbb6-98cb-483b-94e3-c0a1c69f0ec7	a85fcee4-204c-4853-9e0e-71962d2b717d	1	191	197	help your numbers grow. Lean into that your, you've got people here locally like the guy	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
2ca6ccd2-fd7a-4558-a531-4f202e2e1a9a	a85fcee4-204c-4853-9e0e-71962d2b717d	2	199	205	Curtis Engels who was the crap or king. You know, he's, he is somebody in the port of the	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
158f6d30-eb7b-4773-a55a-f4e387701e23	a85fcee4-204c-4853-9e0e-71962d2b717d	3	205	213	body business. And obviously, people looked up to him and said, hey, if Ed's doing it or if Curtis is	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
95bcae7b-83c3-4a2f-9b66-1276ec9118f4	a85fcee4-204c-4853-9e0e-71962d2b717d	4	213	219	doing that, then I'm going to sign up here, too. You know, so you never know. You never know. But it	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
3a283889-fbdc-467e-8677-07fec8aa0aac	a85fcee4-204c-4853-9e0e-71962d2b717d	5	219	227	is worth something. I love it. Oh my gosh. I can talk to you forever. And you are welcome back any	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
de2dee6e-40ae-4592-9943-7749fb06f864	a85fcee4-204c-4853-9e0e-71962d2b717d	6	227	230	time because I, I like that you think outside.	neutral	\N	2ac4d568-938e-4ee5-8a87-f3e8827487e3	\N	2026-06-09 14:19:42.995277+00
\.


--
-- Name: chapters chapters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chapters
    ADD CONSTRAINT chapters_pkey PRIMARY KEY (id);


--
-- Name: embeddings embeddings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.embeddings
    ADD CONSTRAINT embeddings_pkey PRIMARY KEY (id);


--
-- Name: episodes episodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.episodes
    ADD CONSTRAINT episodes_pkey PRIMARY KEY (id);


--
-- Name: fact_checked_claims fact_checked_claims_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_checked_claims
    ADD CONSTRAINT fact_checked_claims_pkey PRIMARY KEY (id);


--
-- Name: pipeline_batches pipeline_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_batches
    ADD CONSTRAINT pipeline_batches_pkey PRIMARY KEY (id);


--
-- Name: podcasts podcasts_feed_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.podcasts
    ADD CONSTRAINT podcasts_feed_url_key UNIQUE (feed_url);


--
-- Name: podcasts podcasts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.podcasts
    ADD CONSTRAINT podcasts_pkey PRIMARY KEY (id);


--
-- Name: transcript_lines transcript_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transcript_lines
    ADD CONSTRAINT transcript_lines_pkey PRIMARY KEY (id);


--
-- Name: chapters uq_chapters_episode_idx; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chapters
    ADD CONSTRAINT uq_chapters_episode_idx UNIQUE (episode_id, chapter_idx);


--
-- Name: episodes uq_episodes_podcast_guid; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.episodes
    ADD CONSTRAINT uq_episodes_podcast_guid UNIQUE (podcast_id, guid);


--
-- Name: fact_checked_claims uq_fact_checked_claims_chapter_idx; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_checked_claims
    ADD CONSTRAINT uq_fact_checked_claims_chapter_idx UNIQUE (chapter_id, claim_idx);


--
-- Name: transcript_lines uq_transcript_lines_chapter_idx; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transcript_lines
    ADD CONSTRAINT uq_transcript_lines_chapter_idx UNIQUE (chapter_id, line_idx);


--
-- Name: idx_chapters_episode_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chapters_episode_id ON public.chapters USING btree (episode_id);


--
-- Name: idx_chapters_preprocessing_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chapters_preprocessing_updated_at ON public.chapters USING btree (preprocessing_updated_at);


--
-- Name: idx_chapters_processing_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chapters_processing_updated_at ON public.chapters USING btree (processing_updated_at);


--
-- Name: idx_chapters_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chapters_title ON public.chapters USING btree (title);


--
-- Name: idx_embeddings_processing_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_embeddings_processing_updated_at ON public.embeddings USING btree (processing_updated_at);


--
-- Name: idx_embeddings_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_embeddings_vector ON public.embeddings USING hnsw (embedding public.halfvec_cosine_ops);


--
-- Name: idx_episodes_ingestion_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_ingestion_updated_at ON public.episodes USING btree (ingestion_updated_at);


--
-- Name: idx_episodes_podcast_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_podcast_id ON public.episodes USING btree (podcast_id);


--
-- Name: idx_episodes_preprocessing_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_preprocessing_updated_at ON public.episodes USING btree (preprocessing_updated_at);


--
-- Name: idx_episodes_processing_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_processing_updated_at ON public.episodes USING btree (processing_updated_at);


--
-- Name: idx_episodes_source_system_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_source_system_updated_at ON public.episodes USING btree (source_system_updated_at);


--
-- Name: idx_fact_checked_claims_chapter_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fact_checked_claims_chapter_id ON public.fact_checked_claims USING btree (chapter_id);


--
-- Name: idx_fact_checked_claims_processing_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fact_checked_claims_processing_updated_at ON public.fact_checked_claims USING btree (processing_updated_at);


--
-- Name: idx_pipeline_batches_mode; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pipeline_batches_mode ON public.pipeline_batches USING btree (load_mode);


--
-- Name: idx_pipeline_batches_stage_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pipeline_batches_stage_status ON public.pipeline_batches USING btree (stage, status);


--
-- Name: idx_podcasts_ingestion_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcasts_ingestion_updated_at ON public.podcasts USING btree (ingestion_updated_at);


--
-- Name: idx_podcasts_preprocessing_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcasts_preprocessing_updated_at ON public.podcasts USING btree (preprocessing_updated_at);


--
-- Name: idx_podcasts_processing_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcasts_processing_updated_at ON public.podcasts USING btree (processing_updated_at);


--
-- Name: idx_podcasts_source_system_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcasts_source_system_updated_at ON public.podcasts USING btree (source_system_updated_at);


--
-- Name: idx_transcript_lines_chapter_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transcript_lines_chapter_id ON public.transcript_lines USING btree (chapter_id);


--
-- Name: idx_transcript_lines_preprocessing_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transcript_lines_preprocessing_updated_at ON public.transcript_lines USING btree (preprocessing_updated_at);


--
-- Name: idx_transcript_lines_processing_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transcript_lines_processing_updated_at ON public.transcript_lines USING btree (processing_updated_at);


--
-- Name: uq_embeddings_chapter; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_embeddings_chapter ON public.embeddings USING btree (chapter_id) WHERE (level = 'chapter'::public.embedding_level);


--
-- Name: uq_embeddings_episode; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_embeddings_episode ON public.embeddings USING btree (episode_id) WHERE (level = 'episode'::public.embedding_level);


--
-- Name: uq_embeddings_podcast; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_embeddings_podcast ON public.embeddings USING btree (podcast_id) WHERE (level = 'podcast'::public.embedding_level);


--
-- Name: uq_episodes_guid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_episodes_guid ON public.episodes USING btree (guid);


--
-- Name: uq_podcasts_guid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_podcasts_guid ON public.podcasts USING btree (guid);


--
-- Name: chapters chapters_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chapters
    ADD CONSTRAINT chapters_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.pipeline_batches(id) ON DELETE SET NULL;


--
-- Name: chapters chapters_episode_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chapters
    ADD CONSTRAINT chapters_episode_id_fkey FOREIGN KEY (episode_id) REFERENCES public.episodes(id) ON DELETE CASCADE;


--
-- Name: embeddings embeddings_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.embeddings
    ADD CONSTRAINT embeddings_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.pipeline_batches(id) ON DELETE SET NULL;


--
-- Name: embeddings embeddings_chapter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.embeddings
    ADD CONSTRAINT embeddings_chapter_id_fkey FOREIGN KEY (chapter_id) REFERENCES public.chapters(id) ON DELETE CASCADE;


--
-- Name: embeddings embeddings_episode_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.embeddings
    ADD CONSTRAINT embeddings_episode_id_fkey FOREIGN KEY (episode_id) REFERENCES public.episodes(id) ON DELETE CASCADE;


--
-- Name: embeddings embeddings_podcast_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.embeddings
    ADD CONSTRAINT embeddings_podcast_id_fkey FOREIGN KEY (podcast_id) REFERENCES public.podcasts(id) ON DELETE CASCADE;


--
-- Name: episodes episodes_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.episodes
    ADD CONSTRAINT episodes_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.pipeline_batches(id) ON DELETE SET NULL;


--
-- Name: episodes episodes_podcast_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.episodes
    ADD CONSTRAINT episodes_podcast_id_fkey FOREIGN KEY (podcast_id) REFERENCES public.podcasts(id) ON DELETE CASCADE;


--
-- Name: fact_checked_claims fact_checked_claims_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_checked_claims
    ADD CONSTRAINT fact_checked_claims_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.pipeline_batches(id) ON DELETE SET NULL;


--
-- Name: fact_checked_claims fact_checked_claims_chapter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_checked_claims
    ADD CONSTRAINT fact_checked_claims_chapter_id_fkey FOREIGN KEY (chapter_id) REFERENCES public.chapters(id) ON DELETE CASCADE;


--
-- Name: podcasts podcasts_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.podcasts
    ADD CONSTRAINT podcasts_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.pipeline_batches(id) ON DELETE SET NULL;


--
-- Name: transcript_lines transcript_lines_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transcript_lines
    ADD CONSTRAINT transcript_lines_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.pipeline_batches(id) ON DELETE SET NULL;


--
-- Name: transcript_lines transcript_lines_chapter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transcript_lines
    ADD CONSTRAINT transcript_lines_chapter_id_fkey FOREIGN KEY (chapter_id) REFERENCES public.chapters(id) ON DELETE CASCADE;



