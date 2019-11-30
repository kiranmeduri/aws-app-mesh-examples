package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/aws/aws-xray-sdk-go/xray"
)

const defaultPort = "8080"
const defaultStage = "default"

func getServerPort() string {
	port := os.Getenv("PORT")
	if port != "" {
		return port
	}

	return defaultPort
}

func getStage() string {
	stage := os.Getenv("STAGE")
	if stage != "" {
		return stage
	}

	return defaultStage
}

func getBackendURL() string {
	backendURL := os.Getenv("BACKEND_URL")
	if backendURL != "" {
		return backendURL
	}

	return "https://www.amazon.com"
}

func getXRAYAppName() string {
	appName := os.Getenv("XRAY_APP_NAME")
	if appName != "" {
		return appName
	}

	return "front"
}

type pingHandler struct{}

func (h *pingHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	log.Println("ping requested, reponding with HTTP 200")
	writer.WriteHeader(http.StatusOK)
}

type externalHandler struct{}

func (h *externalHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	client := xray.Client(&http.Client{})
	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf(getBackendURL()), nil)
	if err != nil {
		writer.WriteHeader(http.StatusInternalServerError)
		writer.Write([]byte("500 - Unexpected Error"))
		return
	}

	resp, err := client.Do(req.WithContext(request.Context()))
	if err != nil {
		writer.WriteHeader(http.StatusInternalServerError)
		writer.Write([]byte("500 - Unexpected Error"))
		return
	}

	defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		writer.WriteHeader(http.StatusInternalServerError)
		writer.Write([]byte("500 - Unexpected Error"))
		return
	}

	fmt.Fprintf(writer, `%s`, strings.TrimSpace(string(body)))
}

func main() {
	log.Println("Starting server, listening on port " + getServerPort())
	xraySegmentNamer := xray.NewFixedSegmentNamer(getXRAYAppName())
	http.Handle("/ping", xray.Handler(xraySegmentNamer, &pingHandler{}))
	http.Handle("/ext", xray.Handler(xraySegmentNamer, &externalHandler{}))
	log.Fatal(http.ListenAndServe(":"+getServerPort(), nil))
}
