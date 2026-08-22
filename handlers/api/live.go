package api

import (
	"akpa/server/internal"
	"bufio"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

var connMutex sync.Mutex

// HandleLiveView processes the dynamic /live/{id} route
func HandleLiveView(w http.ResponseWriter, r *http.Request) {

	// 1. Extract the dynamic {id} path value from the request
	liveID := r.PathValue("id")
	fmt.Println("The live ID is:", liveID)

	connMutex.Lock()
	defer connMutex.Unlock()

	// Remove the id from the requestUri
	newPath := strings.Replace(r.RequestURI, "live/"+liveID, "", 1)
	newPath = strings.ReplaceAll(newPath, "//", "/")

	r.URL.Path = newPath

	// Optional: Validate or look up the ID in your database here
	conn := internal.AppRegistry.FindTunnelByID(liveID)
	if conn == nil {
		http.Error(w, "Live stream not found", http.StatusNotFound)
		return
	}

	// 2. Ask connection to render the live page
	conn.SetWriteDeadline(time.Now().Add(30 * time.Second))
	err := r.Write(conn)
	if err != nil {
		fmt.Println("Error writing request to connection:", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		internal.AppRegistry.RemoveTunnel(liveID)
		return
	}

	fmt.Println("The request path is:", r.URL.Path)
	fmt.Println("The request uri is:", r.RequestURI)

	// 3. Read ONLY one HTTP response from the connection (does NOT wait for connection EOF)
	conn.SetReadDeadline(time.Now().Add(30 * time.Second))
	resp, err := http.ReadResponse(bufio.NewReader(conn), r)
	if err != nil {
		fmt.Println("Error reading response from tunnel:", err)
		http.Error(w, "Bad Gateway", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	// 4. Copy headers to browser
	for k, v := range resp.Header {
		w.Header()[k] = v
	}

	contentType := resp.Header.Get("Content-Type")
	if strings.Contains(contentType, "text/html") {
		bodyBytes, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err == nil {
			htmlContent := string(bodyBytes)
			// Inject <base> right after <head>
			baseTag := fmt.Sprintf("<base href=\"/live/%s/\">", liveID)
			if strings.Contains(htmlContent, "<head>") {
				htmlContent = strings.Replace(htmlContent, "<head>", "<head>"+baseTag, 1)
			} else {
				htmlContent = baseTag + htmlContent
			}

			w.Header().Set("Content-Length", fmt.Sprintf("%d", len(htmlContent)))
			w.WriteHeader(resp.StatusCode)
			w.Write([]byte(htmlContent))
			return
		}
	}

	w.WriteHeader(resp.StatusCode)

	// 5. Stream response body back to browser
	_, err = io.Copy(w, resp.Body)
	if err != nil {
		fmt.Println("Error streaming response body:", err)
	}
}
