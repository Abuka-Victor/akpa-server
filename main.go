package main

import (
	"akpa/server/handlers/api"
	"akpa/server/internal"
	"akpa/server/templates"

	"fmt"
	"net/http"
	"sync"

	"github.com/a-h/templ"
	"github.com/joho/godotenv"
)

func main() {

	if err := godotenv.Load(); err != nil {
		fmt.Println("No .env file found, relying on system environment variables")
	}

	var wg sync.WaitGroup
	wg.Add(2)

	fmt.Println("Starting AKPA server...")
	go func() {
		defer wg.Done()
		internal.RunTCPServer()
	}()

	// start the http server
	go func() {
		defer wg.Done()

		mux := http.NewServeMux()

		fileServer := http.FileServer(http.Dir("./static"))
		mux.Handle("/static/", http.StripPrefix("/static", fileServer))

		// mux.HandleFunc("/favicon.ico", func(w http.ResponseWriter, r *http.Request) {
		// 	http.ServeFile(w, r, "./static/favicon.ico")
		// })

		// mux.HandleFunc("/robots.txt", func(w http.ResponseWriter, r *http.Request) {
		// 	http.ServeFile(w, r, "./static/robots.txt")
		// })

		// mux.HandleFunc("/sitemap.xml", func(w http.ResponseWriter, r *http.Request) {
		// 	http.ServeFile(w, r, "./static/sitemap.xml")
		// })

		// mux.Handle("/", templ.Handler(templates.Layout(templates.PageData{
		// 	Title: "Akpa Server",
		// })))

		mux.HandleFunc("GET /install.sh", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "text/plain; charset=utf-8")
			w.Header().Set("Cache-Control", "public, max-age=300")
			http.ServeFile(w, r, "./static/install.sh")
		})

		mux.Handle("/", templ.Handler(templates.Home(templates.HomeData{
			Title:       "Akpa Server",
			InstallCmd:  "`curl -fsSL https://akpa.victorabuka.com/install.sh | bash`",
			Version:     "1.0",
			GitHubURL:   "https://github.com/Abuka-Victor/akpa-cli",
			LiveTunnels: internal.AppRegistry.TunnelCount(),
		})))

		mux.HandleFunc("GET /live/{id}/", api.HandleLiveView)
		mux.HandleFunc("GET /live/{id}", api.HandleLiveView)

		err := http.ListenAndServe(":8081", mux)
		if err != nil {
			fmt.Println("Error starting HTTP server:", err)
		}
	}()

	wg.Wait()
}
