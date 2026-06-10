package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"media-lens/backend/internal/model"
)

// @Summary      Kapitel eines Episodes
// @Description  Get chapters for an episode. Returns 202 if segmentation is not ready yet.
// @Tags         chapters
// @Produce      json
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  {object}  model.ChaptersResponse
// @Success      202  "Segmentation not ready"
// @Failure      404  {object}  model.ApiError
// @Router       /episodes/{id}/chapters [get]
func (h *Handler) GetChapters(c *gin.Context) {
	episode := h.getEpisodeOrAbort(c, c.Param("id"))
	if episode == nil {
		return
	}

	chapters, err := h.Chapters.ListByEpisodeID(c.Request.Context(), episode.ID)
	if err != nil {
		respondInternalError(c, err)
		return
	}

	if len(chapters) == 0 {
		c.Status(http.StatusAccepted)
		return
	}

	c.JSON(http.StatusOK, model.ChaptersResponse{
		EpisodeID: episode.ID,
		Chapters:  chapters,
	})
}
