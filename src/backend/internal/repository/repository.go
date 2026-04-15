package repository

import (
	"context"
	"database/sql"
	"encoding/base64"
	"fmt"
	"strconv"
	"strings"

	"github.com/lib/pq"
	"media-lens/backend/internal/model"
)

// --- Episode Repository ---

type EpisodeRepository interface {
	ListAll(ctx context.Context) ([]model.Episode, error)
	GetByID(ctx context.Context, id string) (*model.Episode, error)
	ListByPodcastID(ctx context.Context, podcastID string) ([]model.Episode, error)
	ListDistinctPodcasts(ctx context.Context) ([]model.PodcastSummary, error)
	ListPaginated(ctx context.Context, q string, cursor string, limit int) (episodes []model.Episode, total int, err error)
}

type postgresEpisodeRepo struct {
	db *sql.DB
}

func NewEpisodeRepository(db *sql.DB) EpisodeRepository {
	return &postgresEpisodeRepo{db: db}
}

func (r *postgresEpisodeRepo) ListAll(ctx context.Context) ([]model.Episode, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, title, COALESCE(podcast_id, ''), COALESCE(podcast_name, ''),
		       published_at, duration_seconds,
		       COALESCE(audio_path, ''), COALESCE(xml_path, ''),
		       COALESCE(cover_path, ''), ingested_at
		FROM episodes
		ORDER BY ingested_at DESC
	`)
	if err != nil {
		return nil, fmt.Errorf("query episodes: %w", err)
	}
	defer rows.Close()

	return scanEpisodes(rows)
}

func (r *postgresEpisodeRepo) GetByID(ctx context.Context, id string) (*model.Episode, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT id, title, COALESCE(podcast_id, ''), COALESCE(podcast_name, ''),
		       published_at, duration_seconds,
		       COALESCE(audio_path, ''), COALESCE(xml_path, ''),
		       COALESCE(cover_path, ''), ingested_at
		FROM episodes
		WHERE id = $1
	`, id)

	ep, err := scanEpisode(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("scan episode: %w", err)
	}
	return ep, nil
}

func (r *postgresEpisodeRepo) ListByPodcastID(ctx context.Context, podcastID string) ([]model.Episode, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, title, COALESCE(podcast_id, ''), COALESCE(podcast_name, ''),
		       published_at, duration_seconds,
		       COALESCE(audio_path, ''), COALESCE(xml_path, ''),
		       COALESCE(cover_path, ''), ingested_at
		FROM episodes
		WHERE podcast_id = $1
		ORDER BY ingested_at DESC
	`, podcastID)
	if err != nil {
		return nil, fmt.Errorf("query episodes by podcast_id: %w", err)
	}
	defer rows.Close()

	return scanEpisodes(rows)
}

func (r *postgresEpisodeRepo) ListDistinctPodcasts(ctx context.Context) ([]model.PodcastSummary, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT COALESCE(podcast_id, 'unknown'), COUNT(*), MAX(ingested_at)
		FROM episodes
		GROUP BY podcast_id
		ORDER BY MAX(ingested_at) DESC
	`)
	if err != nil {
		return nil, fmt.Errorf("query distinct podcasts: %w", err)
	}
	defer rows.Close()

	var summaries []model.PodcastSummary
	for rows.Next() {
		var s model.PodcastSummary
		if err := rows.Scan(&s.PodcastID, &s.EpisodeCount, &s.LatestEpisode); err != nil {
			return nil, fmt.Errorf("scan podcast summary: %w", err)
		}
		summaries = append(summaries, s)
	}
	return summaries, rows.Err()
}

// ListPaginated implements cursor-based pagination with optional free-text search.
// Cursor encodes the ingested_at+id of the last seen row (base64).
func (r *postgresEpisodeRepo) ListPaginated(ctx context.Context, q string, cursor string, limit int) ([]model.Episode, int, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	var whereClauses []string
	var args []interface{}
	argIdx := 1

	// Free-text search on title and podcast_name
	if q != "" {
		pattern := "%" + q + "%"
		whereClauses = append(whereClauses, fmt.Sprintf("(title ILIKE $%d OR COALESCE(podcast_name, '') ILIKE $%d)", argIdx, argIdx))
		args = append(args, pattern)
		argIdx++
	}

	// Cursor-based pagination: cursor is base64(ingested_at|id)
	if cursor != "" {
		decoded, err := base64.StdEncoding.DecodeString(cursor)
		if err == nil {
			parts := strings.SplitN(string(decoded), "|", 2)
			if len(parts) == 2 {
				whereClauses = append(whereClauses, fmt.Sprintf(
					"(ingested_at, id) < ($%d::timestamptz, $%d::uuid)", argIdx, argIdx+1))
				args = append(args, parts[0], parts[1])
				argIdx += 2
			}
		}
	}

	whereSQL := ""
	if len(whereClauses) > 0 {
		whereSQL = "WHERE " + strings.Join(whereClauses, " AND ")
	}

	// Count total matching rows
	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM episodes %s", whereSQL)
	var total int
	if err := r.db.QueryRowContext(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count episodes: %w", err)
	}

	// Fetch page
	dataQuery := fmt.Sprintf(`
		SELECT id, title, COALESCE(podcast_id, ''), COALESCE(podcast_name, ''),
		       published_at, duration_seconds,
		       COALESCE(audio_path, ''), COALESCE(xml_path, ''),
		       COALESCE(cover_path, ''), ingested_at
		FROM episodes
		%s
		ORDER BY ingested_at DESC, id DESC
		LIMIT $%d
	`, whereSQL, argIdx)
	args = append(args, limit)

	rows, err := r.db.QueryContext(ctx, dataQuery, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("query paginated episodes: %w", err)
	}
	defer rows.Close()

	episodes, err := scanEpisodes(rows)
	if err != nil {
		return nil, 0, err
	}

	return episodes, total, nil
}

// EncodeCursor creates a cursor string from an episode.
func EncodeCursor(ep model.Episode) string {
	raw := ep.IngestedAt.Format("2006-01-02T15:04:05.999999Z07:00") + "|" + ep.ID
	return base64.StdEncoding.EncodeToString([]byte(raw))
}

func scanEpisode(row *sql.Row) (*model.Episode, error) {
	var ep model.Episode
	var durationSeconds sql.NullInt64
	err := row.Scan(&ep.ID, &ep.Title, &ep.PodcastID, &ep.PodcastName,
		&ep.PublishedAt, &durationSeconds,
		&ep.AudioPath, &ep.XMLPath, &ep.CoverPath, &ep.IngestedAt)
	if err != nil {
		return nil, err
	}
	if durationSeconds.Valid {
		d := int(durationSeconds.Int64)
		ep.DurationSeconds = &d
	}
	return &ep, nil
}

func scanEpisodes(rows *sql.Rows) ([]model.Episode, error) {
	var episodes []model.Episode
	for rows.Next() {
		var ep model.Episode
		var durationSeconds sql.NullInt64
		if err := rows.Scan(&ep.ID, &ep.Title, &ep.PodcastID, &ep.PodcastName,
			&ep.PublishedAt, &durationSeconds,
			&ep.AudioPath, &ep.XMLPath, &ep.CoverPath, &ep.IngestedAt); err != nil {
			return nil, fmt.Errorf("scan episode row: %w", err)
		}
		if durationSeconds.Valid {
			d := int(durationSeconds.Int64)
			ep.DurationSeconds = &d
		}
		episodes = append(episodes, ep)
	}
	return episodes, rows.Err()
}

// --- Section Repository ---

type SectionRepository interface {
	ListByEpisodeID(ctx context.Context, episodeID string) ([]model.PodcastSection, error)
	SearchText(ctx context.Context, query string, limit int) ([]model.SearchResult, error)
}

type postgresSectionRepo struct {
	db *sql.DB
}

func NewSectionRepository(db *sql.DB) SectionRepository {
	return &postgresSectionRepo{db: db}
}

func (r *postgresSectionRepo) ListByEpisodeID(ctx context.Context, episodeID string) ([]model.PodcastSection, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, episode_id, section_idx, COALESCE(text, ''),
		       COALESCE(sentiment, ''), COALESCE(sentiment_score, 0),
		       COALESCE(topics, '{}'), processed_at
		FROM podcast_sections
		WHERE episode_id = $1
		ORDER BY section_idx ASC
	`, episodeID)
	if err != nil {
		return nil, fmt.Errorf("query sections: %w", err)
	}
	defer rows.Close()

	var sections []model.PodcastSection
	for rows.Next() {
		var s model.PodcastSection
		if err := rows.Scan(&s.ID, &s.EpisodeID, &s.SectionIdx, &s.Text,
			&s.Sentiment, &s.SentimentScore,
			pq.Array(&s.Topics), &s.ProcessedAt); err != nil {
			return nil, fmt.Errorf("scan section row: %w", err)
		}
		sections = append(sections, s)
	}
	return sections, rows.Err()
}

func (r *postgresSectionRepo) SearchText(ctx context.Context, query string, limit int) ([]model.SearchResult, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	rows, err := r.db.QueryContext(ctx, `
		SELECT s.episode_id, e.title, s.section_idx, s.text, 
		       COALESCE(s.sentiment, ''), 1.0 as score
		FROM podcast_sections s
		JOIN episodes e ON e.id = s.episode_id
		WHERE s.text ILIKE '%' || $1 || '%'
		ORDER BY s.processed_at DESC
		LIMIT $2
	`, query, limit)
	if err != nil {
		return nil, fmt.Errorf("search sections: %w", err)
	}
	defer rows.Close()

	var results []model.SearchResult
	for rows.Next() {
		var r model.SearchResult
		if err := rows.Scan(&r.EpisodeID, &r.EpisodeTitle, &r.SectionIdx,
			&r.Snippet, &r.Sentiment, &r.Score); err != nil {
			return nil, fmt.Errorf("scan search result: %w", err)
		}
		results = append(results, r)
	}
	return results, rows.Err()
}

// --- Topic Repository ---

type TopicRepository interface {
	ListByEpisodeID(ctx context.Context, episodeID string) ([]model.TopicCard, error)
}

type postgresTopicRepo struct {
	db *sql.DB
}

func NewTopicRepository(db *sql.DB) TopicRepository {
	return &postgresTopicRepo{db: db}
}

func (r *postgresTopicRepo) ListByEpisodeID(ctx context.Context, episodeID string) ([]model.TopicCard, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, topic, start_time, emotion::text, COALESCE(summary, '')
		FROM topics
		WHERE episode_id = $1
		ORDER BY start_time ASC
	`, episodeID)
	if err != nil {
		return nil, fmt.Errorf("query topics: %w", err)
	}
	defer rows.Close()

	var topics []model.TopicCard
	for rows.Next() {
		var t model.TopicCard
		if err := rows.Scan(&t.ID, &t.Topic, &t.StartTime, &t.Emotion, &t.Summary); err != nil {
			return nil, fmt.Errorf("scan topic row: %w", err)
		}
		topics = append(topics, t)
	}
	return topics, rows.Err()
}

// --- Transcript Repository ---

type TranscriptRepository interface {
	ListByEpisodeID(ctx context.Context, episodeID string) ([]model.TranscriptLine, error)
}

type postgresTranscriptRepo struct {
	db *sql.DB
}

func NewTranscriptRepository(db *sql.DB) TranscriptRepository {
	return &postgresTranscriptRepo{db: db}
}

func (r *postgresTranscriptRepo) ListByEpisodeID(ctx context.Context, episodeID string) ([]model.TranscriptLine, error) {
	// Join with fact_checks to determine has_fact_flag per line.
	// A transcript line has a fact flag if any fact_check shares its start_time.
	rows, err := r.db.QueryContext(ctx, `
		SELECT tl.id, tl.start_time, tl.text,
		       CASE WHEN fc.id IS NOT NULL THEN true ELSE false END AS has_fact_flag
		FROM transcript_lines tl
		LEFT JOIN fact_checks fc ON fc.episode_id = tl.episode_id AND fc.start_time = tl.start_time
		WHERE tl.episode_id = $1
		ORDER BY tl.start_time ASC
	`, episodeID)
	if err != nil {
		return nil, fmt.Errorf("query transcript lines: %w", err)
	}
	defer rows.Close()

	var lines []model.TranscriptLine
	for rows.Next() {
		var l model.TranscriptLine
		if err := rows.Scan(&l.ID, &l.StartTime, &l.Text, &l.HasFactFlag); err != nil {
			return nil, fmt.Errorf("scan transcript line: %w", err)
		}
		lines = append(lines, l)
	}
	return lines, rows.Err()
}

// --- FactCheck Repository ---

type FactCheckRepository interface {
	ListByEpisodeID(ctx context.Context, episodeID string) ([]model.FactCheckClaim, error)
}

type postgresFactCheckRepo struct {
	db *sql.DB
}

func NewFactCheckRepository(db *sql.DB) FactCheckRepository {
	return &postgresFactCheckRepo{db: db}
}

func (r *postgresFactCheckRepo) ListByEpisodeID(ctx context.Context, episodeID string) ([]model.FactCheckClaim, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, start_time, claim, verdict::text, COALESCE(explanation, ''),
		       COALESCE(sources, '{}')
		FROM fact_checks
		WHERE episode_id = $1
		ORDER BY start_time ASC
	`, episodeID)
	if err != nil {
		return nil, fmt.Errorf("query fact checks: %w", err)
	}
	defer rows.Close()

	var claims []model.FactCheckClaim
	for rows.Next() {
		var c model.FactCheckClaim
		if err := rows.Scan(&c.ID, &c.StartTime, &c.Claim, &c.Verdict,
			&c.Explanation, pq.Array(&c.Sources)); err != nil {
			return nil, fmt.Errorf("scan fact check: %w", err)
		}
		claims = append(claims, c)
	}
	return claims, rows.Err()
}

// --- Conversation Repository ---

type ConversationRepository interface {
	Create(ctx context.Context, episodeID string) (string, error)
	Exists(ctx context.Context, conversationID string) (bool, error)
	GetEpisodeID(ctx context.Context, conversationID string) (string, error)
}

type postgresConversationRepo struct {
	db *sql.DB
}

func NewConversationRepository(db *sql.DB) ConversationRepository {
	return &postgresConversationRepo{db: db}
}

func (r *postgresConversationRepo) Create(ctx context.Context, episodeID string) (string, error) {
	var id string
	err := r.db.QueryRowContext(ctx, `
		INSERT INTO conversations (episode_id) VALUES ($1)
		RETURNING id
	`, episodeID).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("create conversation: %w", err)
	}
	return id, nil
}

func (r *postgresConversationRepo) Exists(ctx context.Context, conversationID string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(ctx, `
		SELECT EXISTS(SELECT 1 FROM conversations WHERE id = $1)
	`, conversationID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check conversation exists: %w", err)
	}
	return exists, nil
}

func (r *postgresConversationRepo) GetEpisodeID(ctx context.Context, conversationID string) (string, error) {
	var episodeID string
	err := r.db.QueryRowContext(ctx, `
		SELECT episode_id FROM conversations WHERE id = $1
	`, conversationID).Scan(&episodeID)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("get conversation episode_id: %w", err)
	}
	return episodeID, nil
}

// Helper to parse limit from string with bounds
func ParseLimit(s string, defaultVal, maxVal int) int {
	if s == "" {
		return defaultVal
	}
	v, err := strconv.Atoi(s)
	if err != nil || v <= 0 {
		return defaultVal
	}
	if v > maxVal {
		return maxVal
	}
	return v
}
