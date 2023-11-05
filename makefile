# For full Kind v0.17 release notes: https://github.com/kubernetes-sigs/kind/releases/tag/v0.17.0
#
# Other commands to install.
# go install github.com/divan/expvarmon@latest
#
# http://sales-service.sales-system.svc.cluster.local:4000/debug/pprof
# curl -il sales-service.sales-system.svc.cluster.local:4000/debug/vars
# curl -il sales-service.sales-system.svc.cluster.local:3000/test


# app/services/sales-api/main.go dosyasını çalıştırır ve app/tooling/logfmt/main.go ile log formatlarını düzenler.
run:
	go run app/services/sales-api/main.go | go run app/tooling/logfmt/main.go

# : app/services/sales-api/main.go dosyasını --help parametresi ile çalıştırarak kullanılabilir komutlar ve yardım bilgilerini gösterir.
run-help:
	go run app/services/sales-api/main.go --help

#go mod tidy komutunu çalıştırarak projedeki bağımlılıkları temizler ve go mod vendor ile bağımlılıkları vendor dizini altına kopyalar.
tidy:
	go mod tidy
	go mod vendor

# expvarmon aracını kullanarak :4000 portunda çalışan uygulamanın performans metriklerini görüntüler.
metrics-local:
	expvarmon -ports=":4000" -vars="build,requests,goroutines,errors,panics,mem:memstats.Alloc"

#: expvarmon aracını kullanarak sales-service.sales-system.svc.cluster.local:4000 adresinde çalışan uygulamanın metriklerini görüntüler.
metrics-view:
	expvarmon -ports="sales-service.sales-system.svc.cluster.local:4000" -vars="build,requests,goroutines,errors,panics,mem:memstats.Alloc"

# ==============================================================================
# Building containers

# $(shell git rev-parse --short HEAD)
VERSION := 1.0

all: sales

# : docker build komutu ile sales-api Docker imajını belirtilen versiyon ve build argümanlarıyla oluşturur.
sales:
	docker build \
		-f zarf/docker/dockerfile.sales-api \
		-t sales-api:$(VERSION) \
		--build-arg BUILD_REF=$(VERSION) \
		--build-arg BUILD_DATE=`date -u +"%Y-%m-%dT%H:%M:%SZ"` \
		.

# ==============================================================================
# Running from within k8s/kind

GOLANG       := golang:1.19
ALPINE       := alpine:3.17
KIND         := kindest/node:v1.25.3
POSTGRES     := postgres:15-alpine
VAULT        := hashicorp/vault:1.12
ZIPKIN       := openzipkin/zipkin:2.23
TELEPRESENCE := docker.io/datawire/tel2:2.10.4

KIND_CLUSTER := ardan-starter-cluster

# : kind aracını kullanarak Kubernetes cluster'ı oluşturur ve telepresence imajını yükler.
dev-kind:
	kind create cluster \
		--image kindest/node:v1.25.3@sha256:f52781bc0d7a19fb6c405c2af83abfeb311f130707a0e219175677e366cc45d1 \
		--name $(KIND_CLUSTER) \
		--config zarf/k8s/dev/kind-config.yaml
	kubectl wait --timeout=120s --namespace=local-path-storage --for=condition=Available deployment/local-path-provisioner

	kind load docker-image $(TELEPRESENCE) --name $(KIND_CLUSTER)

	telepresence --context=kind-$(KIND_CLUSTER) helm install

#  kind ile oluşturulan Kubernetes cluster'ına telepresence aracı ile bağlanır.
dev-up: dev-kind
	telepresence --context=kind-$(KIND_CLUSTER) connect

# : WSL2 üzerinde telepresence ile cluster'a bağlanır.
dev-up-wsl2: dev-kind
	sudo telepresence --context=kind-$(KIND_CLUSTER) connect

# telepresence bağlantısını keser ve kind ile oluşturulan cluster'ı siler.
dev-down:
	telepresence quit -s
	kind delete cluster --name $(KIND_CLUSTER)

# : Kubernetes cluster'ında çalışan node'lar, servisler ve pod'lar hakkında bilgi verir.
dev-status:
	kubectl get nodes -o wide
	kubectl get svc -o wide
	kubectl get pods -o wide --watch --all-namespaces

#  kind aracını kullanarak yerel Docker imajını Kubernetes cluster'ına yükler.
dev-load:
	kind load docker-image sales-api:$(VERSION) --name $(KIND_CLUSTER)

# : kustomize ile Kubernetes kaynaklarını oluşturur ve kubectl apply ile uygular.
dev-apply:
	kustomize build zarf/k8s/dev/sales | kubectl apply -f -
	kubectl wait --timeout=120s --namespace=sales-system --for=condition=Available deployment/sales

#  Kubernetes cluster'ında sales deployment'ını yeniden başlatır.
dev-restart:
	kubectl rollout restart deployment sales --namespace=sales-system

# : sales uygulamasına ait logları getirir ve logfmt ile formatlar.
dev-logs:
	kubectl logs --namespace=sales-system -l app=sales --all-containers=true -f --tail=100 --max-log-requests=6 | go run app/tooling/logfmt/main.go -service=SALES-API

# : Kubernetes cluster'ındaki node ve servisleri detaylı bir şekilde açıklar.
dev-describe:
	kubectl describe nodes
	kubectl describe svc

# : sales deployment'ının detaylarını açıklar.
dev-describe-deployment:
	kubectl describe deployment --namespace=sales-system sales

#  sales uygulamasına ait pod'ların detaylarını açıklar.
dev-describe-sales:
	kubectl describe pod --namespace=sales-system -l app=sales

#: telepresence trafiğini yöneten pod'ların detaylarını açıklar.
dev-describe-tel:
	kubectl describe pod --namespace=ambassador -l app=traffic-manager

# : Tüm imajları yükler ve sales deployment'ını yeniden başlatır.
dev-update: all dev-load dev-restart

# Tüm imajları yükler ve Kubernetes kaynaklarını uygular.
dev-update-apply: all dev-load dev-apply
