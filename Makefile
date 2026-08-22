.PHONY: dev
dev:
	@# Run templ, tailwind, and go run concurrently in a single shell session
	templ generate --watch & \
	npx tailwindcss -i ./static/css/global.css -o ./static/css/output.css --watch & \
	go run main.go