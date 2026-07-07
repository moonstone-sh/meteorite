package main

import (
	"os"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
)

var devicePattern = regexp.MustCompile(`^[a-z0-9_-]{1,64}$`)
var filePattern = regexp.MustCompile(`^[a-z0-9_.-]{1,80}$`)

const textContentType = "text/plain; charset=utf-8"

var cpuWork = map[string]time.Duration{
	"50us":  50 * time.Microsecond,
	"100us": 100 * time.Microsecond,
	"250us": 250 * time.Microsecond,
	"500us": 500 * time.Microsecond,
	"1ms":   time.Millisecond,
	"2ms":   2 * time.Millisecond,
	"5ms":   5 * time.Millisecond,
}

var sleepWork = map[string]time.Duration{"1ms": time.Millisecond, "5ms": 5 * time.Millisecond, "10ms": 10 * time.Millisecond}

var workChecksum = map[string]string{"50us": "50", "100us": "100", "250us": "250", "500us": "500", "1ms": "1000", "2ms": "2000", "5ms": "5000"}

func spinFor(d time.Duration) {
	start := time.Now()
	for time.Since(start) < d {
	}
}

func sendText(c *fiber.Ctx, status int, body string) error {
	c.Set(fiber.HeaderContentType, textContentType)
	return c.Status(status).SendString(body)
}

func sendBytes(c *fiber.Ctx, status int, contentType string, body []byte) error {
	c.Set(fiber.HeaderContentType, contentType)
	return c.Status(status).Send(body)
}

func main() {
	// Explicitly set GOMAXPROCS to match available CPUs for benchmark fairness.
	if n := runtime.NumCPU(); n > 0 {
		runtime.GOMAXPROCS(n)
	}

	port := "8080"
	for _, arg := range os.Args[1:] {
		if strings.HasPrefix(arg, "--port=") {
			port = strings.TrimPrefix(arg, "--port=")
		}
	}

	app := fiber.New(fiber.Config{DisableStartupMessage: true, Prefork: true})
	app.Get("/__bench/meta", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"framework":           "go-fiber",
			"runtime":             "go",
			"backend":             "fasthttp",
			"build":               "go-build-release-trimpath-s-w",
			"prefork":             true,
			"keep_alive":          true,
			"gomaxprocs":          runtime.GOMAXPROCS(0),
			"logging_middleware":  false,
			"recovery_middleware": false,
		})
	})
	for _, path := range []string{"/__bench/plain", "/__bench/plain-static", "/__bench/raw", "/__bench/hybrid-zig", "/__bench/hybrid-inline", "/__bench/hybrid-inline-text-literal", "/health", "/hybrid-inline"} {
		app.Get(path, func(c *fiber.Ctx) error { return sendText(c, 200, "ok") })
	}
	app.Get("/__bench/hybrid-inline-params/:id", func(c *fiber.Ctx) error {
		id := c.Params("id")
		if _, err := strconv.ParseUint(id, 10, 64); err != nil {
			return sendText(c, 400, "bad id")
		}
		return sendText(c, 200, id)
	})
	app.Post("/__bench/hybrid-inline-echo", func(c *fiber.Ctx) error { return sendBytes(c, 200, textContentType, c.Body()) })
	app.Get("/__bench/work/cpu/:duration", func(c *fiber.Ctx) error {
		duration := c.Params("duration")
		d, ok := cpuWork[duration]
		if !ok {
			return sendText(c, 404, "not found")
		}
		spinFor(d)
		return sendText(c, 200, "work:cpu:"+duration+":"+workChecksum[duration])
	})
	app.Get("/__bench/work/sleep/:duration", func(c *fiber.Ctx) error {
		duration := c.Params("duration")
		d, ok := sleepWork[duration]
		if !ok {
			return sendText(c, 404, "not found")
		}
		time.Sleep(d)
		return sendText(c, 200, "sleep:"+duration)
	})
	app.Get("/users/:id", func(c *fiber.Ctx) error {
		id := c.Params("id")
		if _, err := strconv.ParseUint(id, 10, 64); err != nil {
			return sendText(c, 400, "bad id")
		}
		return sendBytes(c, 200, "application/json", []byte(id))
	})
	app.Get("/devices/:device_id", func(c *fiber.Ctx) error {
		id := c.Params("device_id")
		if !devicePattern.MatchString(id) {
			return sendText(c, 400, "bad device id")
		}
		return sendBytes(c, 200, "application/json", []byte(id))
	})
	app.Get("/files/:name", func(c *fiber.Ctx) error {
		name := c.Params("name")
		if !filePattern.MatchString(name) {
			return sendText(c, 400, "bad file name")
		}
		return sendText(c, 200, name)
	})
	app.Post("/echo", func(c *fiber.Ctx) error { return sendBytes(c, 200, textContentType, c.Body()) })

	if err := app.Listen("127.0.0.1:" + port); err != nil {
		panic(err)
	}
}
