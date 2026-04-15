package handlers

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// SyncPlayback godoc
// @Summary      Playback-Position per SSE
// @Description  Server-Sent Events stream for playback synchronization (stubbed).
// @Tags         sync
// @Produce      text/event-stream
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  "SSE stream"
// @Failure      404  {object}  model.ApiError
// @Router       /episodes/{id}/sync [get]
func (h *Handler) SyncPlayback(c *gin.Context) {
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

	c.Header("Content-Type", "text/event-stream")
	c.Header("Cache-Control", "no-cache")
	c.Header("Connection", "keep-alive")
	c.Status(http.StatusOK)

	// Stubbed: send a few sample position events then close
	flusher := c.Writer.(http.Flusher)
	positions := []int{0, 30, 60, 90, 120}

	for _, pos := range positions {
		select {
		case <-c.Request.Context().Done():
			return
		default:
			progress := 0.0
			if episode.DurationSeconds != nil && *episode.DurationSeconds > 0 {
				progress = float64(pos) / float64(*episode.DurationSeconds) * 100
			}

			fmt.Fprintf(c.Writer, "event: position\ndata: {\"current_time\":%d,\"active_transcript_line_id\":\"\",\"progress_percent\":%.1f}\n\n", pos, progress)
			flusher.Flush()
			time.Sleep(1 * time.Second)
		}
	}

	// Send analysis_ready event
	fmt.Fprintf(c.Writer, "event: analysis_ready\ndata: {\"episode_id\":\"%s\"}\n\n", episodeID)
	flusher.Flush()
}
