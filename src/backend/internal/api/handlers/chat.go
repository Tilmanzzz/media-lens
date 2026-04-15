package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"media-lens/backend/internal/model"
)

// CreateConversation godoc
// @Summary      Neue Chat-Session starten
// @Description  Create a new chat conversation for an episode.
// @Tags         chat
// @Accept       json
// @Produce      json
// @Param        body  body      model.CreateConversationRequest  true  "Episode ID"
// @Success      201   {object}  model.CreateConversationResponse
// @Failure      400   {object}  model.ApiError
// @Router       /chat/conversations [post]
func (h *Handler) CreateConversation(c *gin.Context) {
	var req model.CreateConversationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "invalid_request", "Ungültige Anfrage: "+err.Error())
		return
	}

	episode := h.getEpisodeOrAbort(c, req.EpisodeID)
	if episode == nil {
		return
	}

	conversationID, err := h.Conversations.Create(c.Request.Context(), req.EpisodeID)
	if err != nil {
		respondInternalError(c, err)
		return
	}

	c.JSON(http.StatusCreated, model.CreateConversationResponse{
		ConversationID: conversationID,
	})
}

// SendMessage godoc
// @Summary      Nachricht senden — Antwort kommt als Stream
// @Description  Send a message and receive a stubbed NDJSON streaming response.
// @Tags         chat
// @Accept       json
// @Produce      application/x-ndjson
// @Param        id    path      string                     true  "Conversation ID (UUID)"
// @Param        body  body      model.SendMessageRequest   true  "User message"
// @Success      200   "NDJSON stream of ChatStreamChunk"
// @Failure      400   {object}  model.ApiError
// @Failure      404   {object}  model.ApiError
// @Router       /chat/conversations/{id}/messages [post]
func (h *Handler) SendMessage(c *gin.Context) {
	conversationID := c.Param("id")

	var req model.SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "invalid_request", "Ungültige Anfrage: "+err.Error())
		return
	}

	exists, err := h.Conversations.Exists(c.Request.Context(), conversationID)
	if err != nil {
		respondInternalError(c, err)
		return
	}
	if !exists {
		respondError(c, http.StatusNotFound, "conversation_not_found", "Conversation mit dieser ID existiert nicht.")
		return
	}

	// Stubbed streaming response
	c.Header("Content-Type", "application/x-ndjson")
	c.Status(http.StatusOK)

	encoder := json.NewEncoder(c.Writer)
	stubTokens := []string{
		"Das ", "ist ", "eine ", "Stub-Antwort. ",
		"LLM-Integration ", "folgt ", "in ", "einer ", "späteren ", "Version.",
	}

	for _, token := range stubTokens {
		chunk := model.ChatStreamChunk{Type: "token", Delta: token}
		if err := encoder.Encode(chunk); err != nil {
			return
		}
		c.Writer.(http.Flusher).Flush()
		time.Sleep(50 * time.Millisecond)
	}

	done := model.ChatStreamChunk{Type: "done"}
	_ = encoder.Encode(done)
	c.Writer.(http.Flusher).Flush()
}
