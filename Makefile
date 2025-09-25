BIND_VERSION=9.21.12

.PHONY: build
build:
	docker build -f Dockerfile --progress=plain \
		--build-arg BIND_VERSION=$(BIND_VERSION) \
		--target final \
		-t "bind:local" \
		.

.PHONY: run
run:
	docker run -it --rm \
		-v $(PWD)/example-configs:/etc/bind/local-config:ro \
		bind:local

dev:
	docker buildx build --platform linux/amd64,linux/386,linux/arm64,linux/arm/v7 \
		--build-arg BIND_VERSION=$(BIND_VERSION) \
		--target final --tag jonasal/bind:dev .

push-dev:
	docker buildx build --platform linux/amd64,linux/arm64 \
		--build-arg BIND_VERSION=$(BIND_VERSION)\
		--target final --tag jonasal/bind:dev --pull --push .
