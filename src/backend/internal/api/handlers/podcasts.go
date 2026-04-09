package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"media-lens/backend/internal/model"
)

// ListPodcasts godoc
// @Summary      List all podcasts
// @Description  Get a list of all podcasts that are currently being tracked.
// @Tags         podcasts
// @Produce      json
// @Success      200  {array}   model.Podcast
// @Router       /podcasts [get]
func ListPodcasts(c *gin.Context) {
	podcasts := []model.Podcast{
		{
			ID:          "p1",
			Title:       "The Go Programming Podcast",
			Description: "A podcast about Go.",
			RSSURL:      "https://example.com/go/rss",
			CreatedAt:   time.Now(),
		},
	}
	c.JSON(http.StatusOK, podcasts)
}

// AddPodcast godoc
// @Summary      Add a new podcast
// @Description  Provide an RSS URL to start tracking a new podcast.
// @Tags         podcasts
// @Accept       json
// @Produce      json
// @Param        podcast  body      model.Podcast  true  "Podcast to add"
// @Success      201      {object}  model.Podcast
// @Router       /podcasts [post]
func AddPodcast(c *gin.Context) {
	var podcast model.Podcast
	if err := c.ShouldBindJSON(&podcast); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	podcast.ID = "p2" // Mock ID
	podcast.CreatedAt = time.Now()
	c.JSON(http.StatusCreated, podcast)
}

// SearchTranscripts godoc
// @Summary      Search through transcripts
// @Description  Search all transcribed episodes for a specific keyword or phrase.
// @Tags         search
// @Produce      json
// @Param        q    query     string  true  "Search query"
// @Success      200  {array}   model.SearchResult
// @Router       /search [get]
func SearchTranscripts(c *gin.Context) {
	query := c.Query("q")
	results := []model.SearchResult{
		{
			EpisodeID: "e1",
			Snippet:   "...match for " + query + " in the transcript...",
			Score:     0.98,
		},
	}
	c.JSON(http.StatusOK, results)
}
