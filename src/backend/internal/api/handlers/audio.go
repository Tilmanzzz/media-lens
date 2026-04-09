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
// @Failure      404  {object}  map[string]string
// @Failure      500  {object}  map[string]string
// @Router       /audio-url/{id} [get]
func (h *Handler) GetAudioURL(c *gin.Context) {
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
	if episode.AudioPath == "" {
		c.JSON(http.StatusNotFound, gin.H{"error": "no audio file available for this episode"})
		return
	}

	expiry := 1 * time.Hour
	presignedURL, err := storage.GeneratePresignedURL(c.Request.Context(), h.Minio, h.Config.MinioBucket, episode.AudioPath, expiry)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate audio URL"})
		return
	}

	c.JSON(http.StatusOK, model.AudioURLResponse{
		URL:       presignedURL.String(),
		ExpiresIn: expiry.String(),
	})
}
