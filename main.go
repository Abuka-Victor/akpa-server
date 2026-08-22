package main

import (
	"akpa/server/internal"
	"akpa/server/templates"
	"fmt"
	"net/http"
	"sync"

	"github.com/a-h/templ"
)

func main() {
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

		mux.Handle("/", templ.Handler(templates.Layout(templates.PageData{
			Title: "Akpa Server",
		})))

		err := http.ListenAndServe(":8081", mux)
		if err != nil {
			fmt.Println("Error starting HTTP server:", err)
		}
	}()

	wg.Wait()
}
