// Package handlers manages the different versions of the API.
package handlers

import (
	"net/http"
	"os"
	"service-training/app/services/sales-api/handlers/v1/testgrp"
	"service-training/foundation/web"

	"go.uber.org/zap"
)

// APIMuxConfig contains all the mandatory systems required by handlers.
type APIMuxConfig struct {
	Shutdown chan os.Signal
	Log      *zap.SugaredLogger
}

// APIMux constructs a http.Handler with all application routes defined.
func APIMux(cfg APIMuxConfig) *web.App {
	app := web.NewApp(cfg.Shutdown)

	app.Handle(http.MethodGet, "/test", testgrp.Status)

	return app
}