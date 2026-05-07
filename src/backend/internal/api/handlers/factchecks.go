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
	episode := h.getEpisodeOrAbort(c, c.Param("id"))
	if episode == nil {
		return
	}

	claims, err := h.FactChecks.ListByEpisodeID(c.Request.Context(), episode.ID)
	if err != nil {
		respondInternalError(c, err)
		return
	}
	if claims == nil {
		claims = []model.FactCheckClaim{}
	}

	c.JSON(http.StatusOK, model.FactChecksResponse{
		EpisodeID: episode.ID,
		Claims:    claims,
	})
}
