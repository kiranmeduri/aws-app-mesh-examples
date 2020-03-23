package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-xray-sdk-go/xray"
)

const defaultPort = "9080"
const defaultAppName = "unknown"

type ServiceResponse struct {
	Name            string             `json:"name,omitempty"`
	Error           string             `json:"error,omitempty"`
	Message         string             `json:"message,omitempty"`
	BackendMessages []*ServiceResponse `json:"backendMessages,omitempty"`
	TimeMs          int64              `json:"timeMs"`
}

func getServerPort() string {
	port := os.Getenv("PORT")
	if port != "" {
		return port
	}

	return defaultPort
}

func getAppName() string {
	node := os.Getenv("APP_NAME")
	if node != "" {
		return node
	}

	return defaultAppName
}

func getBackends() []string {
	backendsStr := os.Getenv("BACKENDS")
	if backendsStr != "" {
		return strings.Split(backendsStr, ",")
	}

	return []string{}
}

func getInitSleepDuration() int {
	sleepDurationStr := os.Getenv("INIT_SLEEP_SECONDS")
	if sleepDurationStr == "" {
		return 0
	}

	sleepDuration, err := strconv.Atoi(sleepDurationStr)
	if err != nil {
		log.Fatalf("Invalid INIT_SLEEP_SECONDS value: %s", err)
	}
	return sleepDuration
}

type appHandler struct{}

func (h *appHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	start := time.Now()
	backends := getBackends()
	backendsHeader := request.Header.Get("backends")
	if backendsHeader != "" {
		backends = strings.Split(backendsHeader, ",")
	}

	//From https://github.com/bcelenza/mockingbird/blob/master/main.go
	latencyHeader := request.Header.Get("latency")
	if latencyHeader != "" {
		latency, err := time.ParseDuration(latencyHeader)
		if err != nil {
			writer.WriteHeader(400)
			return
		}
		time.Sleep(latency)
	}

	backendMessages := make([]*ServiceResponse, len(backends))
	var wg sync.WaitGroup
	for idx, backend := range backends {
		wg.Add(1)
		go func(request *http.Request, idx int, backend string, wg *sync.WaitGroup) {
			defer wg.Done()
			start := time.Now()
			req, _ := http.NewRequest("GET", "http://"+backend, nil)
			for k, v := range request.Header {
				req.Header[k] = v
			}
			resp, err := http.DefaultClient.Do(req)
			end := time.Since(start)
			backendMessages[idx] = &ServiceResponse{
				Name:   backend,
				TimeMs: int64(end / time.Millisecond),
			}
			if err != nil {
				log.Printf("Error calling %s: %s", backend, err)
				backendMessages[idx].Error = fmt.Sprintf("Error making http call %s", err)
				return
			}

			if resp.StatusCode != http.StatusOK {
				log.Printf("Error received response with %d(%s) status from %s", resp.StatusCode, resp.Status, backend)
				backendMessages[idx].Error = fmt.Sprintf("Received response with %d(%s) status", resp.StatusCode, resp.Status)
				return
			}

			defer resp.Body.Close()
			body, err := ioutil.ReadAll(resp.Body)
			if err != nil {
				log.Printf("Error reading response from %s: %s", backend, err)
				backendMessages[idx].Error = fmt.Sprintf("Error reading response %s", err)
				return
			}

			var backendResponse ServiceResponse
			err = json.Unmarshal(body, &backendResponse)
			if err != nil {
				log.Printf("Error unmarshalling json response(%s) from %s: %s", string(body), backend, err)
				backendMessages[idx].Error = fmt.Sprintf("Error unmarshalling json %s", err)
				backendMessages[idx].Message = fmt.Sprintf("Content = %s", string(body))
				return
			}
			backendMessages[idx] = &backendResponse
		}(request, idx, backend, &wg)
	}
	wg.Wait()

	backendsWithError := 0
	for _, b := range backendMessages {
		if b.Error != "" {
			backendsWithError++
		}
	}

	if backendsWithError > 0 {
		http.Error(writer, fmt.Sprintf("%d backends failed", backendsWithError), http.StatusInternalServerError)
		return
	}

	end := time.Since(start)
	res := ServiceResponse{
		Name:            getAppName(),
		Message:         fmt.Sprintf("Hi from %s", getAppName()),
		BackendMessages: backendMessages,
		TimeMs:          int64(end / time.Millisecond),
	}
	resJSON, err := json.Marshal(res)
	if err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
		return
	}
	log.Printf("resJSON = %s", resJSON)
	writer.Header().Set("Content-Type", "application/json")
	writer.Write(resJSON)
}

type pingHandler struct{}

func (h *pingHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	writer.WriteHeader(http.StatusOK)
}

func main() {
	initSleepDuration := getInitSleepDuration()
	if initSleepDuration > 0 {
		log.Printf("Sleeping for %d seconds before starting server", initSleepDuration)
		time.Sleep(time.Second * time.Duration(initSleepDuration))
	}
	log.Println("starting server, listening on port " + getServerPort())
	xraySegmentNamer := xray.NewFixedSegmentNamer(getAppName())
	http.Handle("/", xray.Handler(xraySegmentNamer, &appHandler{}))
	http.Handle("/ping", &pingHandler{})
	http.ListenAndServe(":"+getServerPort(), nil)
}
