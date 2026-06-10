// @title           Audiolens API
// @version         1.0
// @description     Podcast analysis backend — episodes, chapters, transcripts, fact-checks, chat.
// @host            localhost:8080
// @BasePath        /api/v1
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"

	"media-lens/backend/internal/api/handlers"
	"media-lens/backend/internal/config"
	"media-lens/backend/internal/database"
	"media-lens/backend/internal/embedder"
	"media-lens/backend/internal/repository"
	"media-lens/backend/internal/storage"
	"media-lens/backend/internal/vectorstore"
	_ "media-lens/backend/docs"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	var db *database.DB
	for i := 0; i < 5; i++ {
		db, err = database.NewPostgresDB(cfg.PostgresURL)
		if err == nil {
			break
		}
		log.Printf("Database connection attempt %d/5 failed: %v", i+1, err)
		time.Sleep(2 * time.Second)
	}
	if err != nil {
		log.Fatalf("Failed to connect to database after retries: %v", err)
	}

	minioClient, err := storage.NewMinioClient(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to MinIO: %v", err)
	}

	ollamaClient := embedder.NewOllamaClient(cfg.OllamaURL, cfg.EmbeddingModel)
	pgvectorClient := vectorstore.NewPgVectorClient(db)

	episodeRepo := repository.NewEpisodeRepository(db)
	chapterRepo := repository.NewChapterRepository(db)
	transcriptRepo := repository.NewTranscriptRepository(db)
	factCheckRepo := repository.NewFactCheckRepository(db)
	conversationRepo := repository.NewConversationRepository()

	h := &handlers.Handler{
		Episodes:      episodeRepo,
		Chapters:      chapterRepo,
		Transcripts:   transcriptRepo,
		FactChecks:    factCheckRepo,
		Conversations: conversationRepo,
		Minio:         minioClient,
		Config:        cfg,
		DB:            db,
		Embedder:      ollamaClient,
		VectorStore:   pgvectorClient,
	}

	r := gin.Default()

	r.Use(handlers.MaxBodySize(1 << 20))
	r.Use(cors.New(cors.Config{
		AllowOrigins:     cfg.CORSOrigins,
		AllowMethods:     []string{"GET", "POST", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	v1 := r.Group("/api/v1")
	{
		v1.GET("/health", h.HealthCheck)
		v1.GET("/search", h.SemanticSearch)

		v1.GET("/episodes", h.ListEpisodes)
		v1.GET("/episodes/:id", handlers.ValidateUUID("id"), h.GetEpisode)
		v1.GET("/episodes/:id/chapters", handlers.ValidateUUID("id"), h.GetChapters)
		v1.GET("/episodes/:id/transcript", handlers.ValidateUUID("id"), h.GetTranscript)
		v1.GET("/episodes/:id/fact-checks", handlers.ValidateUUID("id"), h.GetFactChecks)
		v1.GET("/episodes/:id/sync", handlers.ValidateUUID("id"), h.SyncPlayback)

		v1.POST("/chat/conversations", h.CreateConversation)
		v1.POST("/chat/conversations/:id/messages", handlers.ValidateUUID("id"), h.SendMessage)
	}

	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	srv := &http.Server{
		Addr:    cfg.ServerPort,
		Handler: r,
	}

	go func() {
		log.Printf("Starting server on %s", cfg.ServerPort)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	db.Close()
	log.Println("Server exited")
}
