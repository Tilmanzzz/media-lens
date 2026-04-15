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
	episode := h.getEpisodeOrAbort(c, c.Param("id"))
	if episode == nil {
		return
	}

	topics, err := h.Topics.ListByEpisodeID(c.Request.Context(), episode.ID)
	if err != nil {
		respondInternalError(c, err)
		return
	}

	if len(topics) == 0 {
		c.Status(http.StatusAccepted)
		return
	}

	c.JSON(http.StatusOK, model.TopicsResponse{
		EpisodeID: episode.ID,
		Topics:    topics,
	})
}
