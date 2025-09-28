BIND_VERSION="9.21.12"

.PHONY: build
build:
	docker build -f Dockerfile --progress=plain \
		--build-arg BIND_VERSION=$(BIND_VERSION) \
		--target final \
		-t "bind:local" \
		.

.PHONY: build-alpine
build-alpine:
	docker build -f Dockerfile --progress=plain \
		--build-arg BIND_VERSION=$(BIND_VERSION) \
		--target final-alpine \
		-t "bind:local" \
		.

.PHONY: run
run:
	if [ ! -d "$(PWD)/cache" ]; then sudo install -m 0776 -o root -g 101 -d $(PWD)/cache; fi
	docker run -it --rm \
		-v $(PWD)/example-configs:/etc/bind/local-config:ro \
		-v $(PWD)/cache:/var/cache/bind \
		bind:local

dev:
	docker buildx build --platform linux/amd64,linux/386,linux/arm64,linux/arm/v7 \
		--build-arg BIND_VERSION=$(BIND_VERSION) \
		--target final --tag jonasal/bind:dev .

push-dev:
	docker buildx build --platform linux/amd64,linux/arm64 \
		--build-arg BIND_VERSION=$(BIND_VERSION)\
		--target final --tag jonasal/bind:dev --pull --push .
