package handlers

import (
	"database/sql"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/minio/minio-go/v7"
	"media-lens/backend/internal/config"
	"media-lens/backend/internal/model"
	"media-lens/backend/internal/repository"
	"media-lens/backend/internal/storage"
)

// Handler holds all dependencies for HTTP handlers.
type Handler struct {
	Episodes      repository.EpisodeRepository
	Sections      repository.SectionRepository
	Topics        repository.TopicRepository
	Transcripts   repository.TranscriptRepository
	FactChecks    repository.FactCheckRepository
	Conversations repository.ConversationRepository
	Minio         *minio.Client
	Config        *config.Config
	DB            *sql.DB
}

// respondError sends a standardized ApiError JSON response.
func respondError(c *gin.Context, status int, errCode, message string) {
	c.JSON(status, model.ApiError{
		Error:   errCode,
		Message: message,
		Status:  status,
	})
}

// episodeToCard converts an Episode to an EpisodeCard, generating a presigned cover URL.
func (h *Handler) episodeToCard(c *gin.Context, ep model.Episode) model.EpisodeCard {
	card := model.EpisodeCard{
		ID:          ep.ID,
		Title:       ep.Title,
		PodcastName: ep.PodcastName,
		PublishedAt: formatDate(ep.PublishedAt),
	}
	if ep.DurationSeconds != nil {
		card.DurationSeconds = *ep.DurationSeconds
	}
	if ep.CoverPath != "" {
		url, err := storage.GeneratePresignedURL(c.Request.Context(), h.Minio, h.Config.MinioBucket, ep.CoverPath, 1*time.Hour)
		if err == nil {
			card.CoverURL = url.String()
		}
	}
	return card
}

// episodeToDetail converts an Episode to an EpisodeDetail.
func (h *Handler) episodeToDetail(c *gin.Context, ep model.Episode) model.EpisodeDetail {
	detail := model.EpisodeDetail{
		ID:          ep.ID,
		Title:       ep.Title,
		PodcastName: ep.PodcastName,
		PublishedAt: formatDate(ep.PublishedAt),
	}
	if ep.DurationSeconds != nil {
		detail.DurationSeconds = *ep.DurationSeconds
	}
	if ep.CoverPath != "" {
		url, err := storage.GeneratePresignedURL(c.Request.Context(), h.Minio, h.Config.MinioBucket, ep.CoverPath, 1*time.Hour)
		if err == nil {
			detail.CoverURL = url.String()
		}
	}
	return detail
}

func formatDate(t sql.NullTime) string {
	if !t.Valid {
		return ""
	}
	return t.Time.Format("2006-01-02")
}

// ListPodcasts godoc
// @Summary      List all podcasts
// @Description  Get a list of distinct podcasts with episode counts.
// @Tags         podcasts
// @Produce      json
// @Success      200  {array}   model.PodcastSummary
// @Failure      500  {object}  model.ApiError
// @Router       /podcasts [get]
func (h *Handler) ListPodcasts(c *gin.Context) {
	summaries, err := h.Episodes.ListDistinctPodcasts(c.Request.Context())
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", err.Error())
		return
	}
	if summaries == nil {
		summaries = []model.PodcastSummary{}
	}
	c.JSON(http.StatusOK, summaries)
}

// ListEpisodes godoc
// @Summary      Episode-Liste
// @Description  Cursor-based paginated episode list with optional free-text search.
// @Tags         episodes
// @Produce      json
// @Param        q       query     string  false  "Free-text search on title and podcast name"
// @Param        cursor  query     string  false  "Cursor from previous response"
// @Param        limit   query     int     false  "Page size (default 20, max 100)"
// @Success      200  {object}  model.EpisodeListResponse
// @Failure      400  {object}  model.ApiError
// @Router       /episodes [get]
func (h *Handler) ListEpisodes(c *gin.Context) {
	q := c.Query("q")
	cursor := c.Query("cursor")
	limit := repository.ParseLimit(c.Query("limit"), 20, 100)

	episodes, total, err := h.Episodes.ListPaginated(c.Request.Context(), q, cursor, limit)
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", err.Error())
		return
	}

	items := make([]model.EpisodeCard, 0, len(episodes))
	for _, ep := range episodes {
		items = append(items, h.episodeToCard(c, ep))
	}

	var nextCursor *string
	if len(episodes) == limit {
		last := episodes[len(episodes)-1]
		cur := repository.EncodeCursor(last)
		nextCursor = &cur
	}

	c.JSON(http.StatusOK, model.EpisodeListResponse{
		Items:      items,
		NextCursor: nextCursor,
		Total:      total,
	})
}

// GetEpisode godoc
// @Summary      Episode-Detail
// @Description  Get episode detail for the header area above the tabs.
// @Tags         episodes
// @Produce      json
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  {object}  model.EpisodeDetailResponse
// @Failure      404  {object}  model.ApiError
// @Router       /episodes/{id} [get]
func (h *Handler) GetEpisode(c *gin.Context) {
	id := c.Param("id")

	episode, err := h.Episodes.GetByID(c.Request.Context(), id)
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", err.Error())
		return
	}
	if episode == nil {
		respondError(c, http.StatusNotFound, "episode_not_found", "Episode mit dieser ID existiert nicht.")
		return
	}

	c.JSON(http.StatusOK, model.EpisodeDetailResponse{
		Episode: h.episodeToDetail(c, *episode),
	})
}

// GetEpisodeSections godoc
// @Summary      Get sections for an episode
// @Description  Retrieve all podcast sections for a given episode ID.
// @Tags         sections
// @Produce      json
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  {array}   model.PodcastSection
// @Failure      500  {object}  model.ApiError
// @Router       /episodes/{id}/sections [get]
func (h *Handler) GetEpisodeSections(c *gin.Context) {
	id := c.Param("id")

	sections, err := h.Sections.ListByEpisodeID(c.Request.Context(), id)
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", err.Error())
		return
	}
	if sections == nil {
		sections = []model.PodcastSection{}
	}
	c.JSON(http.StatusOK, sections)
}

// SearchTranscripts godoc
// @Summary      Search through section text
// @Description  Search all podcast sections for a keyword or phrase.
// @Tags         search
// @Produce      json
// @Param        q      query     string  true   "Search query"
// @Param        limit  query     int     false  "Max results (default 20, max 100)"
// @Success      200  {array}   model.SearchResult
// @Failure      400  {object}  model.ApiError
// @Failure      500  {object}  model.ApiError
// @Router       /search [get]
func (h *Handler) SearchTranscripts(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		respondError(c, http.StatusBadRequest, "missing_query", "Query parameter 'q' is required.")
		return
	}

	limit := repository.ParseLimit(c.Query("limit"), 20, 100)

	results, err := h.Sections.SearchText(c.Request.Context(), query, limit)
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", err.Error())
		return
	}
	if results == nil {
		results = []model.SearchResult{}
	}
	c.JSON(http.StatusOK, results)
}
