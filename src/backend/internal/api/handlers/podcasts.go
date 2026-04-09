package handlers

import (
	"database/sql"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/minio/minio-go/v7"
	"media-lens/backend/internal/config"
	"media-lens/backend/internal/model"
	"media-lens/backend/internal/repository"
)

type Handler struct {
	Episodes repository.EpisodeRepository
	Sections repository.SectionRepository
	Minio    *minio.Client
	Config   *config.Config
	DB       *sql.DB
}

// ListPodcasts godoc
// @Summary      List all podcasts
// @Description  Get a list of distinct podcasts with episode counts.
// @Tags         podcasts
// @Produce      json
// @Success      200  {array}   model.PodcastSummary
// @Failure      500  {object}  map[string]string
// @Router       /podcasts [get]
func (h *Handler) ListPodcasts(c *gin.Context) {
	summaries, err := h.Episodes.ListDistinctPodcasts(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if summaries == nil {
		summaries = []model.PodcastSummary{}
	}
	c.JSON(http.StatusOK, summaries)
}

// ListEpisodes godoc
// @Summary      List episodes
// @Description  Get episodes, optionally filtered by podcast_id.
// @Tags         episodes
// @Produce      json
// @Param        podcast_id  query     string  false  "Filter by podcast ID"
// @Success      200  {array}   model.Episode
// @Failure      500  {object}  map[string]string
// @Router       /episodes [get]
func (h *Handler) ListEpisodes(c *gin.Context) {
	podcastID := c.Query("podcast_id")

	var (
		episodes []model.Episode
		err      error
	)

	if podcastID != "" {
		episodes, err = h.Episodes.ListByPodcastID(c.Request.Context(), podcastID)
	} else {
		episodes, err = h.Episodes.ListAll(c.Request.Context())
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if episodes == nil {
		episodes = []model.Episode{}
	}
	c.JSON(http.StatusOK, episodes)
}

// GetEpisode godoc
// @Summary      Get a single episode with its sections
// @Description  Retrieve an episode and all its podcast sections by episode ID.
// @Tags         episodes
// @Produce      json
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  {object}  model.EpisodeWithSections
// @Failure      404  {object}  map[string]string
// @Failure      500  {object}  map[string]string
// @Router       /episodes/{id} [get]
func (h *Handler) GetEpisode(c *gin.Context) {
	id := c.Param("id")

	episode, err := h.Episodes.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if episode == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "episode not found"})
		return
	}

	sections, err := h.Sections.ListByEpisodeID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if sections == nil {
		sections = []model.PodcastSection{}
	}

	c.JSON(http.StatusOK, model.EpisodeWithSections{
		Episode:  *episode,
		Sections: sections,
	})
}

// GetEpisodeSections godoc
// @Summary      Get sections for an episode
// @Description  Retrieve all podcast sections for a given episode ID.
// @Tags         sections
// @Produce      json
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  {array}   model.PodcastSection
// @Failure      500  {object}  map[string]string
// @Router       /episodes/{id}/sections [get]
func (h *Handler) GetEpisodeSections(c *gin.Context) {
	id := c.Param("id")

	sections, err := h.Sections.ListByEpisodeID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if sections == nil {
		sections = []model.PodcastSection{}
	}
	c.JSON(http.StatusOK, sections)
}

// SearchTranscripts godoc
// @Summary      Search through section text
// @Description  Search all podcast sections for a keyword or phrase using ILIKE.
// @Tags         search
// @Produce      json
// @Param        q      query     string  true   "Search query"
// @Param        limit  query     int     false  "Max results (default 20, max 100)"
// @Success      200  {array}   model.SearchResult
// @Failure      400  {object}  map[string]string
// @Failure      500  {object}  map[string]string
// @Router       /search [get]
func (h *Handler) SearchTranscripts(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "query parameter 'q' is required"})
		return
	}

	limit := 20
	if l := c.Query("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil {
			limit = parsed
		}
	}

	results, err := h.Sections.SearchText(c.Request.Context(), query, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if results == nil {
		results = []model.SearchResult{}
	}
	c.JSON(http.StatusOK, results)
}
