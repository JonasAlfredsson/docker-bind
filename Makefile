BIND_VERSION="9.21.15"

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

.PHONY: build-downloader
build-downloader:
	docker build -f Dockerfile --progress=plain \
		--build-arg BIND_VERSION=$(BIND_VERSION) \
		--target downloader \
		-t "bind:downloader" \
		.

.PHONY: get-meson-options
get-meson-options: build-downloader
	docker run --rm bind:downloader cat /source/meson.options > .github/current_meson.options

.PHONY: run
run:
	if [ ! -d "$(PWD)/cache" ]; then sudo install -m 0777 -o root -g 101 -d $(PWD)/cache; fi
	docker run -it --rm \
		-v $(PWD)/example-configs:/etc/bind/local-config:ro \
		-v $(PWD)/cache:/var/cache/bind \
		bind:local

.PHONY: rndc-key
rndc-key:
	docker run -it --rm \
		-v $(PWD)/example-configs:/etc/bind/local-config \
		--entrypoint=/bin/sh \
		bind:local \
		-c 'rndc-confgen -a -A hmac-sha256 -b 256 -u "$${BIND_USER}" -c /etc/bind/local-config/rndc.key'

dev:
	docker buildx build --platform linux/amd64,linux/386,linux/arm64,linux/arm/v7 \
		--build-arg BIND_VERSION=$(BIND_VERSION) \
		--target final --tag jonasal/bind:dev .

push-dev:
	docker buildx build --platform linux/amd64,linux/arm64 \
		--build-arg BIND_VERSION=$(BIND_VERSION)\
		--target final --tag jonasal/bind:dev --pull --push .
