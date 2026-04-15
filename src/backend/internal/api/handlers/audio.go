package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"media-lens/backend/internal/model"
	"media-lens/backend/internal/storage"
)

// GetAudioURL godoc
// @Summary      Get a presigned audio URL
// @Description  Generate a presigned MinIO URL for streaming an episode's audio file.
// @Tags         audio
// @Produce      json
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  {object}  model.AudioURLResponse
// @Failure      404  {object}  model.ApiError
// @Failure      500  {object}  model.ApiError
// @Router       /audio-url/{id} [get]
func (h *Handler) GetAudioURL(c *gin.Context) {
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
	if episode.AudioPath == "" {
		respondError(c, http.StatusNotFound, "audio_not_found", "No audio file available for this episode.")
		return
	}

	expiry := 1 * time.Hour
	presignedURL, err := storage.GeneratePresignedURL(c.Request.Context(), h.Minio, h.Config.MinioBucket, episode.AudioPath, expiry)
	if err != nil {
		respondError(c, http.StatusInternalServerError, "presign_failed", "Failed to generate audio URL.")
		return
	}

	c.JSON(http.StatusOK, model.AudioURLResponse{
		URL:       presignedURL.String(),
		ExpiresIn: expiry.String(),
	})
}
