package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"media-lens/backend/internal/model"
)

// GetTranscript godoc
// @Summary      Transkript-Zeilen
// @Description  Get transcript lines for an episode. Lines are annotated with has_fact_flag.
// @Tags         transcript
// @Produce      json
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  {object}  model.TranscriptResponse
// @Failure      404  {object}  model.ApiError
// @Router       /episodes/{id}/transcript [get]
func (h *Handler) GetTranscript(c *gin.Context) {
	episode := h.getEpisodeOrAbort(c, c.Param("id"))
	if episode == nil {
		return
	}

	lines, err := h.Transcripts.ListByEpisodeID(c.Request.Context(), episode.ID)
	if err != nil {
		respondInternalError(c, err)
		return
	}
	if lines == nil {
		lines = []model.TranscriptLine{}
	}

	c.JSON(http.StatusOK, model.TranscriptResponse{
		EpisodeID: episode.ID,
		Lines:     lines,
	})
}
