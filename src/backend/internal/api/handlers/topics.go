package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"media-lens/backend/internal/model"
)

// GetTopics godoc
// @Summary      Themen für den Themen-Tab
// @Description  Get topics for an episode. Returns 202 if analysis is not ready yet.
// @Tags         topics
// @Produce      json
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  {object}  model.TopicsResponse
// @Success      202  "Analysis not ready"
// @Failure      404  {object}  model.ApiError
// @Router       /episodes/{id}/topics [get]
func (h *Handler) GetTopics(c *gin.Context) {
	episodeID := c.Param("id")

	episode, err := h.Episodes.GetByID(c.Request.Context(), episodeID)
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", err.Error())
		return
	}
	if episode == nil {
		respondError(c, http.StatusNotFound, "episode_not_found", "Episode mit dieser ID existiert nicht.")
		return
	}

	topics, err := h.Topics.ListByEpisodeID(c.Request.Context(), episodeID)
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", err.Error())
		return
	}

	if topics == nil || len(topics) == 0 {
		c.Status(http.StatusAccepted)
		return
	}

	c.JSON(http.StatusOK, model.TopicsResponse{
		EpisodeID: episodeID,
		Topics:    topics,
	})
}
