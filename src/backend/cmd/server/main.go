// @title           Audiolens API
// @version         1.0
// @description     Podcast analysis backend — episodes, topics, transcripts, fact-checks, chat.
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
	"media-lens/backend/internal/repository"
	"media-lens/backend/internal/storage"
	_ "media-lens/backend/docs"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Connect to PostgreSQL with retry
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

	// Connect to MinIO
	minioClient, err := storage.NewMinioClient(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to MinIO: %v", err)
	}

	// Create repositories
	episodeRepo := repository.NewEpisodeRepository(db)
	topicRepo := repository.NewTopicRepository(db)
	transcriptRepo := repository.NewTranscriptRepository(db)
	factCheckRepo := repository.NewFactCheckRepository(db)
	conversationRepo := repository.NewConversationRepository(db)

	h := &handlers.Handler{
		Episodes:      episodeRepo,
		Topics:        topicRepo,
		Transcripts:   transcriptRepo,
		FactChecks:    factCheckRepo,
		Conversations: conversationRepo,
		Minio:         minioClient,
		Config:        cfg,
		DB:            db,
	}

	r := gin.Default()

	// Global middleware
	r.Use(handlers.MaxBodySize(1 << 20)) // 1 MB max request body
	r.Use(cors.New(cors.Config{
		AllowOrigins:     cfg.CORSOrigins,
		AllowMethods:     []string{"GET", "POST", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	// API v1
	v1 := r.Group("/api/v1")
	{
		v1.GET("/health", h.HealthCheck)

		// Episodes
		v1.GET("/episodes", h.ListEpisodes)
		v1.GET("/episodes/:id", handlers.ValidateUUID("id"), h.GetEpisode)
		v1.GET("/episodes/:id/topics", handlers.ValidateUUID("id"), h.GetTopics)
		v1.GET("/episodes/:id/transcript", handlers.ValidateUUID("id"), h.GetTranscript)
		v1.GET("/episodes/:id/fact-checks", handlers.ValidateUUID("id"), h.GetFactChecks)
		v1.GET("/episodes/:id/sync", handlers.ValidateUUID("id"), h.SyncPlayback)

		// Chat
		v1.POST("/chat/conversations", h.CreateConversation)
		v1.POST("/chat/conversations/:id/messages", handlers.ValidateUUID("id"), h.SendMessage)
	}

	// Swagger UI
	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	// Graceful shutdown
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
