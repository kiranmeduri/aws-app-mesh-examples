package main

import (
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strings"
)

const defaultPort = "8080"

func getServerPort() string {
	port := os.Getenv("PORT")
	if port != "" {
		return port
	}

	return defaultPort
}

func getVsvcProxyEndpoint() (string, error) {
	vsvcProxyEndpoint := os.Getenv("VSVC_PROXY_ENDPOINT")
	if vsvcProxyEndpoint == "" {
		return "", errors.New("VSVC_PROXY_ENDPOINT is not set")
	}
	return vsvcProxyEndpoint, nil
}

func getColorEndpoint() (string, error) {
	colorEndpoint := os.Getenv("COLOR_ENDPOINT")
	if colorEndpoint == "" {
		return "", errors.New("COLOR_ENDPOINT is not set")
	}
	return colorEndpoint, nil

}

type colorHandler struct{}

func (h *colorHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	color, err := getColor(request)
	if err != nil {
		log.Println(fmt.Sprintf("Error from color %+v", err))
		writer.WriteHeader(http.StatusInternalServerError)
		writer.Write([]byte("500 - Unexpected Error"))
		return
	}

	fmt.Fprintf(writer, "color: %s", color)
}

func getColor(request *http.Request) (string, error) {
	vsvcProxyEndpoint, err := getVsvcProxyEndpoint()
	if err != nil {
		return "-n/a-", err
	}
	log.Println("Using vsvcProxy at " + vsvcProxyEndpoint)

	colorEndpoint, err := getColorEndpoint()
	if err != nil {
		return "-n/a-", err
	}
	log.Println("Using color at " + colorEndpoint)

	client := &http.Client{}
	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf("http://%s", vsvcProxyEndpoint), nil)
	if err != nil {
		return "-n/a-", err
	}
	req.Header.Add("X-DST-SVC", colorEndpoint)

	resp, err := client.Do(req.WithContext(request.Context()))
	if err != nil {
		return "-n/a-", err
	}

	defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return "-n/a-", err
	}

	color := strings.TrimSpace(string(body))
	if len(color) < 1 {
		return "-n/a-", errors.New("Empty response from color")
	}

	return color, nil
}

type pingHandler struct{}

func (h *pingHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	log.Println("ping requested, reponding with HTTP 200")
	writer.WriteHeader(http.StatusOK)
}

func main() {
	log.Println("Starting server, listening on port " + getServerPort())

	http.Handle("/color", &colorHandler{})
	http.Handle("/ping", &pingHandler{})
	log.Fatal(http.ListenAndServe(":"+getServerPort(), nil))
}
