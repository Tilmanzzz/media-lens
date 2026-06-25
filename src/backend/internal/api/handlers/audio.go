package handlers

import (
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/minio/minio-go/v7"
)

// @Summary      Audio-Datei streamen
// @Description  Proxy-Endpoint that streams the episode audio from object storage.
// @Tags         episodes
// @Produce      application/octet-stream
// @Param        id   path      string  true  "Episode ID (UUID)"
// @Success      200  "Audio stream"
// @Success      206  "Partial audio stream (range request)"
// @Failure      404  {object}  model.ApiError
// @Router       /episodes/{id}/audio [get]
func (h *Handler) StreamAudio(c *gin.Context) {
	episode := h.getEpisodeOrAbort(c, c.Param("id"))
	if episode == nil {
		return
	}
	if episode.AudioKey == "" {
		respondError(c, http.StatusNotFound, "audio_not_found", "Keine Audio-Datei für diese Episode vorhanden.")
		return
	}

	// Get object info for Content-Length and Content-Type
	info, err := h.Minio.StatObject(c.Request.Context(), h.Config.MinioBucket, episode.AudioKey, minio.StatObjectOptions{})
	if err != nil {
		log.Printf("ERROR stat audio %q: %v", episode.AudioKey, err)
		respondError(c, http.StatusNotFound, "audio_not_found", "Audio-Datei konnte nicht gefunden werden.")
		return
	}

	totalSize := info.Size
	contentType := info.ContentType
	if contentType == "" {
		contentType = "audio/mpeg"
	}

	// Handle Range requests for seeking
	rangeHeader := c.GetHeader("Range")
	if rangeHeader != "" {
		h.handleRangeRequest(c, episode.AudioKey, rangeHeader, totalSize, contentType)
		return
	}

	// Full file response
	obj, err := h.Minio.GetObject(c.Request.Context(), h.Config.MinioBucket, episode.AudioKey, minio.GetObjectOptions{})
	if err != nil {
		log.Printf("ERROR get audio %q: %v", episode.AudioKey, err)
		respondInternalError(c, err)
		return
	}
	defer obj.Close()

	c.Header("Content-Type", contentType)
	c.Header("Content-Length", strconv.FormatInt(totalSize, 10))
	c.Header("Accept-Ranges", "bytes")
	c.Status(http.StatusOK)

	io.Copy(c.Writer, obj)
}

func (h *Handler) handleRangeRequest(c *gin.Context, audioKey, rangeHeader string, totalSize int64, contentType string) {
	// Parse "bytes=start-end"
	rangeHeader = strings.TrimPrefix(rangeHeader, "bytes=")
	parts := strings.SplitN(rangeHeader, "-", 2)
	if len(parts) != 2 {
		c.Status(http.StatusRequestedRangeNotSatisfiable)
		return
	}

	var start, end int64

	if parts[0] == "" {
		// Suffix range: bytes=-500
		suffix, err := strconv.ParseInt(parts[1], 10, 64)
		if err != nil {
			c.Status(http.StatusRequestedRangeNotSatisfiable)
			return
		}
		start = totalSize - suffix
		end = totalSize - 1
	} else {
		var err error
		start, err = strconv.ParseInt(parts[0], 10, 64)
		if err != nil {
			c.Status(http.StatusRequestedRangeNotSatisfiable)
			return
		}
		if parts[1] == "" {
			end = totalSize - 1
		} else {
			end, err = strconv.ParseInt(parts[1], 10, 64)
			if err != nil {
				c.Status(http.StatusRequestedRangeNotSatisfiable)
				return
			}
		}
	}

	if start < 0 || start >= totalSize || end >= totalSize || start > end {
		c.Status(http.StatusRequestedRangeNotSatisfiable)
		return
	}

	length := end - start + 1

	opts := minio.GetObjectOptions{}
	opts.SetRange(start, end)

	obj, err := h.Minio.GetObject(c.Request.Context(), h.Config.MinioBucket, audioKey, opts)
	if err != nil {
		log.Printf("ERROR get audio range %q: %v", audioKey, err)
		respondInternalError(c, err)
		return
	}
	defer obj.Close()

	c.Header("Content-Type", contentType)
	c.Header("Content-Length", strconv.FormatInt(length, 10))
	c.Header("Content-Range", "bytes "+strconv.FormatInt(start, 10)+"-"+strconv.FormatInt(end, 10)+"/"+strconv.FormatInt(totalSize, 10))
	c.Header("Accept-Ranges", "bytes")
	c.Status(http.StatusPartialContent)

	io.Copy(c.Writer, obj)
}
