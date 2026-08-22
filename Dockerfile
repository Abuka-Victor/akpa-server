# syntax=docker/dockerfile:1
#
# akpa server — multi-stage build.
#
# Everything generated (Tailwind CSS, templ Go files) is produced here rather
# than committed, so a deploy can never ship a stale page because someone forgot
# to run a generator before committing.

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Tailwind
# ─────────────────────────────────────────────────────────────────────────────
FROM node:20-alpine AS css

WORKDIR /build

# Tailwind scans your source for class names, so the .templ files must be
# present before it runs — not just the CSS input file.
# tailwind.config.js is kept for future theming. Note that Tailwind v4 does NOT
# read it automatically — it is only used if global.css has a matching
# `@config` line. Copied here so it is available the moment you wire it up.
COPY tailwind.config.js ./
COPY static/css/global.css ./static/css/
COPY templates/ ./templates/

# Tailwind v4. The CLI moved to its own package in v4 — `npx tailwindcss` is v3
# and will not understand an `@import "tailwindcss"` input file.
RUN npx @tailwindcss/cli@4 \
      -i ./static/css/global.css \
      -o ./static/css/output.css \
      --minify

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Go
# ─────────────────────────────────────────────────────────────────────────────
FROM golang:1.25-alpine AS build

WORKDIR /build

# Dependencies first, as their own layer. Docker caches this, so editing a .go
# file doesn't re-download every module.
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Your go.mod uses the `tool` directive (Go 1.24+), so templ is already pinned
# there as a tool dependency. `go tool` runs that exact version — better than
# `go install ...@latest`, which would fetch whatever is newest today and could
# change your generated output between builds.
RUN go tool templ generate

# CGO_ENABLED=0 gives a static binary that runs on a bare Alpine image.
RUN CGO_ENABLED=0 GOOS=linux go build \
      -ldflags="-s -w" \
      -o /build/akpa-server .

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3: runtime
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:3.20

# ca-certificates: needed for any outbound HTTPS.
# tzdata: without it every timestamp the server logs is UTC.
RUN apk add --no-cache ca-certificates tzdata

# Run as a non-root user. If the process is ever compromised, this is the
# difference between an attacker owning a container and owning a container as root.
RUN adduser -D -u 10001 akpa

WORKDIR /app

COPY --from=build /build/akpa-server /app/akpa-server
COPY --from=build /build/static      /app/static
COPY --from=css   /build/static/css/output.css /app/static/css/output.css

RUN chown -R akpa:akpa /app
USER akpa

# 8081 = browsers, via Coolify's proxy
# 7000 = raw TCP from akpa CLI clients, published directly to the host
EXPOSE 8081
EXPOSE 7000

# Your main.go serves ./static relative to the working directory, so this
# must stay /app.
ENTRYPOINT ["/app/akpa-server"]