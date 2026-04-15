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

	lines, err := h.Transcripts.ListByEpisodeID(c.Request.Context(), episodeID)
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", err.Error())
		return
	}
	if lines == nil {
		lines = []model.TranscriptLine{}
	}

	c.JSON(http.StatusOK, model.TranscriptResponse{
		EpisodeID: episodeID,
		Lines:     lines,
	})
}
