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
COPY tailwind.config.js ./
COPY static/css/global.css ./static/css/
COPY templates/ ./templates/

# Pinned so a Tailwind release can't change your CSS without you asking.
# Using Tailwind v4? Replace with: npx @tailwindcss/cli@4 -i ... -o ...
RUN npx @tailwindcss/cli@4 \
      -i ./static/css/global.css \
      -o ./static/css/output.css \
      --minify

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Go
# ─────────────────────────────────────────────────────────────────────────────
FROM golang:1.23-alpine AS build

WORKDIR /build

RUN apk add --no-cache git

# Dependencies first, as their own layer. Docker caches this, so editing a .go
# file doesn't re-download every module.
COPY go.mod go.sum ./
RUN go mod download

# templ is a Go tool, so installing it here costs almost nothing.
RUN go install github.com/a-h/templ/cmd/templ@latest

COPY . .

# Generates templates/*_templ.go from your .templ files.
RUN templ generate

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
