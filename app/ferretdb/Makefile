ifeq (, $(shell which docker-compose 2>/dev/null))
DOCKER_COMPOSE_PLUGIN="true"
endif

default: up view

up: view
ifdef DOCKER_COMPOSE_PLUGIN
	docker compose up -d
else
	docker-compose up -d
endif

view:
	@echo "docker run --rm -it --network=ferretdb --entrypoint=mongosh mongo:5 mongodb://ferretdb/"

log:
	docker logs -f ferretdb

info:
	docker inspect ferretdb | jq

stop:
	docker stop ferretdb;

clean:
	docker stop ferretdb; docker rm -f ferretdb

pull:
	docker pull ferretdb/ferretdb4

rmi:
	docker rmi ferretdb/ferretdb4

save:
	mkdir -p /tmp/docker
	docker save ghcr.io/ferretdb/ferretdb:latest | gzip -9 -c > /tmp/docker/ferretdb.tgz

load:
	cat /tmp/docker/ferretdb.tgz | gzip -d -c - | docker load

.PHONY: default up run view log info stop clean conf dump pull rmi save load