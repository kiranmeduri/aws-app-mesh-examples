package main

import (
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"

	"github.com/aws/aws-xray-sdk-go/xray"
)

const defaultPort = "8080"

// Following cat facts are copied from https://cvillecatcare.com/veterinary-topics/101-amazing-cat-facts-fun-trivia-about-your-feline-friend/
var catFacts = []string{
	"Cats are believed to be the only mammals who don’t taste sweetness.",
	"Cats are nearsighted, but their peripheral vision and night vision are much better than that of humans.",
	"Cats are supposed to have 18 toes (five toes on each front paw; four toes on each back paw).",
	"Cats can jump up to six times their length.",
	"Cats’ claws all curve downward, which means that they can’t climb down trees head-first. Instead, they have to back down the trunk.",
	"Cats’ collarbones don’t connect to their other bones, as these bones are buried in their shoulder muscles.",
	"Cats have 230 bones, while humans only have 206.",
	"Cats have an extra organ that allows them to taste scents on the air, which is why your cat stares at you with her mouth open from time to time.",
	"Cats have whiskers on the backs of their front legs, as well.",
	"Cats have nearly twice the amount of neurons in their cerebral cortex as dogs.",
	"Cats have the largest eyes relative to their head size of any mammal.",
}

func getServerPort() string {
	port := os.Getenv("PORT")
	if port != "" {
		return port
	}

	return defaultPort
}

func getRandomCatFact(request *http.Request) (string, error) {
	randomIndex := rand.Intn(len(catFacts))
	return catFacts[randomIndex], nil
}

func getXRAYAppName() string {
	appName := os.Getenv("XRAY_APP_NAME")
	if appName != "" {
		return appName
	}

	return "cat"
}

type catHandler struct{}

func (h *catHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	catFact, err := getRandomCatFact(request)
	if err != nil {
		writer.WriteHeader(http.StatusInternalServerError)
		writer.Write([]byte("500 - Unexpected Error"))
		return
	}
	fmt.Fprint(writer, catFact)
}

type pingHandler struct{}

func (h *pingHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	log.Println("ping requested, reponding with HTTP 200")
	writer.WriteHeader(http.StatusOK)
}

func main() {
	log.Println("starting server, listening on port " + getServerPort())
	xraySegmentNamer := xray.NewFixedSegmentNamer(getXRAYAppName())
	http.Handle("/", xray.Handler(xraySegmentNamer, &catHandler{}))
	http.Handle("/ping", xray.Handler(xraySegmentNamer, &pingHandler{}))
	http.ListenAndServe(":"+getServerPort(), nil)
}
