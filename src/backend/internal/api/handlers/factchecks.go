package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"media-lens/backend/internal/model"
)

// GetFactChecks godoc
// @Summary      Fact-Check-Flags für die Sidebar
// @Description  Get fact-check claims for an episode.
// @Tags         fact-checks
// @Produce      json
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  {object}  model.FactChecksResponse
// @Failure      404  {object}  model.ApiError
// @Router       /episodes/{id}/fact-checks [get]
func (h *Handler) GetFactChecks(c *gin.Context) {
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

	claims, err := h.FactChecks.ListByEpisodeID(c.Request.Context(), episodeID)
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", err.Error())
		return
	}
	if claims == nil {
		claims = []model.FactCheckClaim{}
	}

	c.JSON(http.StatusOK, model.FactChecksResponse{
		EpisodeID: episodeID,
		Claims:    claims,
	})
}
