package main

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var devicePattern = regexp.MustCompile(`^[a-z0-9_-]{1,64}$`)
var filePattern = regexp.MustCompile(`^[a-z0-9_.-]{1,80}$`)

var cpuWork = map[string]time.Duration{
	"50us":  50 * time.Microsecond,
	"100us": 100 * time.Microsecond,
	"250us": 250 * time.Microsecond,
	"500us": 500 * time.Microsecond,
	"1ms":   time.Millisecond,
	"2ms":   2 * time.Millisecond,
	"5ms":   5 * time.Millisecond,
}

var sleepWork = map[string]time.Duration{
	"1ms":  1 * time.Millisecond,
	"5ms":  5 * time.Millisecond,
	"10ms": 10 * time.Millisecond,
}

var workChecksum = map[string]string{
	"50us": "50", "100us": "100", "250us": "250", "500us": "500", "1ms": "1000", "2ms": "2000", "5ms": "5000",
}

func spinFor(d time.Duration) {
	start := time.Now()
	for time.Since(start) < d {
	}
}

type meta struct {
	Framework string `json:"framework"`
	Runtime   string `json:"runtime"`
	Backend   string `json:"backend"`
}

func text(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(status)
	_, _ = io.WriteString(w, body)
}

func bytes(w http.ResponseWriter, status int, contentType string, body []byte) {
	w.Header().Set("Content-Type", contentType)
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

func main() {
	port := "8080"
	for _, arg := range os.Args[1:] {
		if strings.HasPrefix(arg, "--port=") {
			port = strings.TrimPrefix(arg, "--port=")
		}
	}

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		switch {
		case r.Method == http.MethodGet && path == "/__bench/meta":
			payload, _ := json.Marshal(meta{Framework: "go-nethttp", Runtime: "go", Backend: "net/http"})
			bytes(w, 200, "application/json", payload)
		case r.Method == http.MethodGet && strings.HasPrefix(path, "/__bench/work/cpu/"):
			duration := strings.TrimPrefix(path, "/__bench/work/cpu/")
			d, ok := cpuWork[duration]
			if !ok {
				text(w, 404, "not found")
				return
			}
			spinFor(d)
			text(w, 200, "work:cpu:"+duration+":"+workChecksum[duration])
		case r.Method == http.MethodGet && strings.HasPrefix(path, "/__bench/work/sleep/"):
			duration := strings.TrimPrefix(path, "/__bench/work/sleep/")
			d, ok := sleepWork[duration]
			if !ok {
				text(w, 404, "not found")
				return
			}
			time.Sleep(d)
			text(w, 200, "sleep:"+duration)
		case r.Method == http.MethodGet && (path == "/__bench/plain" || path == "/__bench/plain-static" || path == "/__bench/raw" || path == "/__bench/hybrid-zig" || path == "/__bench/hybrid-inline" || path == "/__bench/hybrid-inline-text-literal" || path == "/health" || path == "/hybrid-inline"):
			text(w, 200, "ok")
		case r.Method == http.MethodGet && strings.HasPrefix(path, "/__bench/hybrid-inline-params/"):
			id := strings.TrimPrefix(path, "/__bench/hybrid-inline-params/")
			if _, err := strconv.ParseUint(id, 10, 64); err != nil {
				text(w, 400, "bad id")
				return
			}
			text(w, 200, id)
		case r.Method == http.MethodPost && path == "/__bench/hybrid-inline-echo":
			body, _ := io.ReadAll(r.Body)
			bytes(w, 200, "text/plain; charset=utf-8", body)
		case r.Method == http.MethodGet && strings.HasPrefix(path, "/users/"):
			id := strings.TrimPrefix(path, "/users/")
			if _, err := strconv.ParseUint(id, 10, 64); err != nil {
				text(w, 400, "bad id")
				return
			}
			bytes(w, 200, "application/json", []byte(id))
		case r.Method == http.MethodGet && strings.HasPrefix(path, "/devices/"):
			id := strings.TrimPrefix(path, "/devices/")
			if !devicePattern.MatchString(id) {
				text(w, 400, "bad device id")
				return
			}
			bytes(w, 200, "application/json", []byte(id))
		case r.Method == http.MethodGet && strings.HasPrefix(path, "/files/"):
			name := strings.TrimPrefix(path, "/files/")
			if !filePattern.MatchString(name) {
				text(w, 400, "bad file name")
				return
			}
			text(w, 200, name)
		case r.Method == http.MethodPost && path == "/echo":
			body, _ := io.ReadAll(r.Body)
			bytes(w, 200, "text/plain; charset=utf-8", body)
		default:
			text(w, 404, "not found")
		}
	})

	server := &http.Server{Addr: "127.0.0.1:" + port, Handler: handler}
	log.Printf("Go net/http listening on http://127.0.0.1:%s", port)
	log.Fatal(server.ListenAndServe())
}
