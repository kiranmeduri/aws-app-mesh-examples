package main

import (
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
)

// Get env var or default
func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

// Get the port to listen on
func getListenAddress() string {
	port := getEnv("PORT", "16001")
	return ":" + port
}

func getDestinationServiceHeader() string {
	return getEnv("DESTINATION_HEADER", "X-DST-SVC")
}

func getDefaultDestination() string {
	return getEnv("DEFAULT_DESTINATION", "localhost")
}

// Given a request send it to the appropriate url
func handleRequestAndRedirect(res http.ResponseWriter, req *http.Request) {
	// We will get to this...
	destSvc := req.Header.Get(getDestinationServiceHeader())
	if destSvc == "" {
		destSvc = getDefaultDestination()
	}

	serveReverseProxy(fmt.Sprintf("http://%s", destSvc), res, req)
}

// Serve a reverse proxy for a given url
func serveReverseProxy(target string, res http.ResponseWriter, req *http.Request) {
	log.Println("Serving reverse proxy for target " + target)
	// parse the url
	url, _ := url.Parse(target)

	// create the reverse proxy
	proxy := httputil.NewSingleHostReverseProxy(url)

	// Update the headers to allow for SSL redirection
	req.URL.Host = url.Host
	req.URL.Scheme = url.Scheme
	req.Header.Set("X-Forwarded-Host", req.Header.Get("Host"))
	req.Host = url.Host

	// Note that ServeHttp is non blocking and uses a go routine under the hood
	proxy.ServeHTTP(res, req)
}

func main() {
	log.Println("Starting server, listening @ " + getListenAddress())
	http.HandleFunc("/", handleRequestAndRedirect)

	if err := http.ListenAndServe(getListenAddress(), nil); err != nil {
		log.Fatalln(err)
	}
}
