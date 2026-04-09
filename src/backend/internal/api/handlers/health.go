package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"media-lens/backend/internal/model"
)

// HealthCheck godoc
// @Summary      Health check
// @Description  Get the health status of the API, including database and MinIO connectivity.
// @Tags         health
// @Produce      json
// @Success      200  {object}  model.HealthStatus
// @Failure      503  {object}  model.HealthStatus
// @Router       /health [get]
func (h *Handler) HealthCheck(c *gin.Context) {
	status := model.HealthStatus{
		Status:   "UP",
		Database: "UP",
		MinIO:    "UP",
	}

	if err := h.DB.Ping(); err != nil {
		status.Status = "DEGRADED"
		status.Database = "DOWN"
	}

	if _, err := h.Minio.BucketExists(c.Request.Context(), h.Config.MinioBucket); err != nil {
		status.Status = "DEGRADED"
		status.MinIO = "DOWN"
	}

	if status.Status != "UP" {
		c.JSON(http.StatusServiceUnavailable, status)
		return
	}

	c.JSON(http.StatusOK, status)
}
