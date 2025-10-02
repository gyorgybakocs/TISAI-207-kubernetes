
BASE_NAMES = POSTGRES LANGFLOW

aws-login: apply-config
	@echo "======================= CONFIGURING AWS CLI =========================="
	@AWS_ACCESS_KEY_ID=$$(kubectl get secret global-secret -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode); \
	AWS_SECRET_ACCESS_KEY=$$(kubectl get secret global-secret -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode); \
	AWS_DEFAULT_REGION=$$(kubectl get configmap global-config -o jsonpath='{.data.AWS_DEFAULT_REGION}'); \
	aws configure set aws_access_key_id "$${AWS_ACCESS_KEY_ID}"; \
	aws configure set aws_secret_access_key "$${AWS_SECRET_ACCESS_KEY}"; \
	aws configure set region "$${AWS_DEFAULT_REGION}";
	@echo "======================= LOGGING IN TO AWS ECR =========================="
	@AWS_ECR_REGISTRY_URL=$$(kubectl get configmap global-config -o jsonpath='{.data.AWS_ECR_REGISTRY_URL}'); \
	aws ecr get-login-password --region $$(kubectl get configmap global-config -o jsonpath='{.data.AWS_DEFAULT_REGION}') | docker login --username AWS --password-stdin "$${AWS_ECR_REGISTRY_URL}"

base-build:
	@echo "----------------- Starting port-forward to local registry -------------------"
	@kubectl port-forward svc/registry 5000:5000 &
	@echo "Waiting for port-forward..." && sleep 5

	@echo "----------------- Pulling, Tagging, and Pushing Base Images -------------------"
	@AWS_ECR_REGISTRY_URL=$$(kubectl get configmap global-config -o jsonpath='{.data.AWS_ECR_REGISTRY_URL}'); \
	IMG_PREFIX=$$(kubectl get configmap global-config -o jsonpath='{.data.IMG_PREFIX}'); \
	ENV_TAG=$$(kubectl get configmap global-config -o jsonpath='{.data.ENV_TAG}'); \
	BITBUCKET_BRANCH=$$(kubectl get configmap global-config -o jsonpath='{.data.BITBUCKET_BRANCH}'); \
	for base_name in $(BASE_NAMES); do \
    		config_map=$$(echo $$base_name | tr 'A-Z' 'a-z')-config; \
    		\
    		IMAGE_NAME=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_IMAGE}"); \
    		VERSION=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_VERSION}"); \
    		LOCAL_TAG=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_BUILT_IMAGE}"); \
    		\
    		ECR_IMAGE_PATH="$${AWS_ECR_REGISTRY_URL}/$${IMG_PREFIX}-$${IMAGE_NAME}:$${ENV_TAG}-$${BITBUCKET_BRANCH}-$${VERSION}"; \
    		LOCAL_IMAGE_PATH="localhost:5000/$${LOCAL_TAG}"; \
    		\
    		echo "--- Processing service: $$base_name ---"; \
    		echo "Pulling from: $${ECR_IMAGE_PATH}"; \
    		docker pull "$${ECR_IMAGE_PATH}"; \
    		echo "Tagging as: $${LOCAL_IMAGE_PATH}"; \
    		docker tag "$${ECR_IMAGE_PATH}" "$${LOCAL_IMAGE_PATH}"; \
    		docker push "$${LOCAL_IMAGE_PATH}"; \
    		echo "--- Done ---"; \
    	done
	@echo "----------------- Verifying images in local registry -------------------"
	@curl -s http://localhost:5000/v2/_catalog
	@echo "----------------- Killing port-forward process -------------------"
	@pkill -f "kubectl port-forward.*5000" || true

# Minikube Management
mk-config:
	@echo "----------------- Configuring Minikube -------------------"
	minikube config unset insecure-registry || true
	minikube config set insecure-registry "registry.default.svc.cluster.local:5000"
	minikube config set insecure-registry "localhost:5000"
	minikube config set memory 6144
	minikube config set cpus 2

mk-up: mk-config
	@echo "----------------- Starting Minikube -------------------"
	minikube start --insecure-registry="192.168.0.0/16"

mk-stop:
	@echo "----------------- Stopping Minikube -------------------"
	-minikube stop

mk-delete:
	@echo "----------------- Deleting Minikube cluster -------------------"
	minikube delete

mk-restart: mk-stop mk-up
	@echo "----------------- Restarting Minikube -------------------"

mk-build: mk-stop mk-delete mk-up mk-setup apply-config apply-instances-config aws-login base-build

# Kubernetes Build
mk-setup:
	@echo "----------------- Mounting working directory into Minikube -------------------"
	docker cp . minikube:/workspace

apply-config:
	@echo "----------------- Applying Kubernetes Registry -------------------"
	kubectl apply -f kubernetes/registry.yaml
	kubectl rollout status deployment registry -n default --timeout=180s
	@echo "----------------- Ensuring registry is ready -------------------"
	@echo "Waiting for registry pod to be ready..."
	@kubectl wait --for=condition=ready pod -l app=registry -n default --timeout=90s
	@echo "Registry pod is ready!"
	@sleep 2
	@echo "----------------- Applying Kubernetes Namespace Limits -------------------"
	kubectl apply -f kubernetes/limits.yaml
	@echo "----------------- Applying Global Configs & Secrets -------------------"
	kubectl apply -f kubernetes/global-config.yaml
	kubectl apply -f kubernetes/global-secret.yaml


apply-instances-config:
	@echo "----------------- Applying Postgres Persistent Volume Claim -------------------"
	kubectl apply -f kubernetes/postgres/postgres-pvc.yaml
	@echo "----------------- Applying Postgres ConfigMaps and Secrets -------------------"
	kubectl apply -f kubernetes/postgres/postgres-init-cm.yaml
	kubectl apply -f kubernetes/postgres/postgres-config.yaml
	kubectl apply -f kubernetes/postgres/postgres-secret.yaml
	@echo "----------------- Applying Langflow Persistent Volume Claim -------------------"
	kubectl apply -f kubernetes/langflow/langflow-pvc.yaml
	@echo "----------------- Applying Langflow ConfigMaps and Secrets -------------------"
	kubectl apply -f kubernetes/langflow/langflow-config.yaml
	kubectl apply -f kubernetes/langflow/langflow-secret.yaml

build-k8s: mk-setup build-k8s-postgres build-k8s-langflow

build-k8s-postgres:
	@echo "----------------- Building Postgres for Kubernetes -------------------"
	kubectl delete job postgres-build --ignore-not-found=true
	kubectl apply -f kubernetes/postgres/postgres-build-job.yaml
	kubectl wait --for=condition=complete job/postgres-build --timeout=90s
	@echo "----------------- Logs for Postgres build job -------------------"
	kubectl logs job/postgres-build --follow

build-k8s-langflow:
	@echo "----------------- Building Langflow for Kubernetes -------------------"
	kubectl delete job langflow-build --ignore-not-found=true
	kubectl apply -f kubernetes/langflow/langflow-build-job.yaml
	kubectl wait --for=condition=complete job/langflow-build --timeout=90s
	@echo "----------------- Logs for Langflow build job -------------------"
	kubectl logs job/langflow-build --follow

# Kubernetes Deployment
up-k8s: down-k8s up-k8s-postgres port-forward-postgres up-k8s-langflow port-forward-langflow
	@echo "----------------- Listing running Kubernetes pods -------------------"
	kubectl get pods

up-k8s-postgres:
	@echo "----------------- Delete Postgres pods... -------------------"
	@kubectl delete pods -l app=postgres

	@echo "----------------- Creating Postgres Service -------------------"
	@POSTGRES_HOST=$$(kubectl get configmap postgres-config -o jsonpath='{.data.POSTGRES_HOST}'); \
    POSTGRES_PORT=$$(kubectl get configmap postgres-config -o jsonpath='{.data.POSTGRES_PORT}'); \
    export POSTGRES_HOST POSTGRES_PORT; \
    envsubst < kubernetes/postgres/postgres-service.yaml | kubectl apply -f -

	@echo "----------------- Deploying Postgres to Kubernetes -------------------"
	@REGISTRY_HOST=$$(minikube ip); \
    POSTGRES_BUILT_IMAGE=$$(kubectl get configmap postgres-config -o jsonpath='{.data.POSTGRES_BUILT_IMAGE}'); \
    POSTGRES_PORT=$$(kubectl get configmap postgres-config -o jsonpath='{.data.POSTGRES_PORT}'); \
    export REGISTRY_HOST POSTGRES_BUILT_IMAGE POSTGRES_PORT; \
	envsubst < kubernetes/postgres/postgres-deployment.yaml | kubectl apply -f -
	@echo "----------------- Waiting for Postgres pod to be ready -------------------"
	kubectl wait --for=condition=ready pod -l app=postgres --timeout=60s

	@echo "----------------- Testing Postgres Service -------------------"
	@POSTGRES_HOST=$$(kubectl get configmap postgres-config -o jsonpath='{.data.POSTGRES_HOST}'); \
	kubectl get service $$POSTGRES_HOST

up-k8s-langflow:
	@echo "----------------- Delete Langflow pods... -------------------"
	@kubectl delete pods -l app=langflow

	@echo "----------------- Creating Langflow Service -------------------"
	@LANGFLOW_SERVICE=$$(kubectl get configmap langflow-config -o jsonpath='{.data.LANGFLOW_SERVICE}'); \
    LANGFLOW_PORT=$$(kubectl get configmap langflow-config -o jsonpath='{.data.LANGFLOW_PORT}'); \
    export LANGFLOW_SERVICE LANGFLOW_PORT; \
    envsubst < kubernetes/langflow/langflow-service.yaml | kubectl apply -f -

	@echo "----------------- Deploying Langflow to Kubernetes -------------------"
	@REGISTRY_HOST=$$(minikube ip); \
    LANGFLOW_BUILT_IMAGE=$$(kubectl get configmap langflow-config -o jsonpath='{.data.LANGFLOW_BUILT_IMAGE}'); \
    LANGFLOW_PORT=$$(kubectl get configmap langflow-config -o jsonpath='{.data.LANGFLOW_PORT}'); \
    export REGISTRY_HOST LANGFLOW_BUILT_IMAGE LANGFLOW_PORT; \
	envsubst < kubernetes/langflow/langflow-deployment.yaml | kubectl apply -f -
	@echo "----------------- Waiting for Langflow pod to be ready -------------------"
	kubectl wait --for=condition=ready pod -l app=langflow --timeout=180s

	@echo "----------------- Testing Langflow Service -------------------"
	@LANGFLOW_SERVICE=$$(kubectl get configmap langflow-config -o jsonpath='{.data.LANGFLOW_SERVICE}'); \
    kubectl get service $$LANGFLOW_SERVICE

down-k8s:
	@echo "----------------- Deleting Deployed Services Commander from Kubernetes -------------------"
	kubectl delete -f kubernetes/postgres/postgres-deployment.yaml --ignore-not-found=true
	kubectl delete -f kubernetes/langflow/langflow-deployment.yaml --ignore-not-found=true

ps-k8s:
	@echo "----------------- Listing running Kubernetes pods -------------------"
	kubectl get pods
	@echo "----------------- Listing Kubernetes services -------------------"
	kubectl get services

#port forwarding
port-forward-postgres:
	@echo "----------------- Forwarding Postgres to localhost (in background)... -------------------"
	@POSTGRES_PORT=$$(kubectl get configmap postgres-config -o jsonpath='{.data.POSTGRES_PORT}'); \
	POSTGRES_REDIRECT_PORT=$$(kubectl get configmap postgres-config -o jsonpath='{.data.POSTGRES_REDIRECT_PORT}'); \
	export POSTGRES_PORT POSTGRES_REDIRECT_PORT; \
	nohup kubectl port-forward "$$(kubectl get pods -l app=postgres -o jsonpath='{.items[0].metadata.name}')" "$${POSTGRES_REDIRECT_PORT}:$${POSTGRES_PORT}" > /dev/null 2>&1 & \
	echo "Waiting for port-forward..." && sleep 5 && \
	echo "----------------- Postgres should be accessible at localhost:$${POSTGRES_REDIRECT_PORT} -------------------"

port-forward-langflow:
	@echo "----------------- Forwarding Langflow to localhost (in background)... -------------------"
	@LANGFLOW_PORT=$$(kubectl get configmap langflow-config -o jsonpath='{.data.LANGFLOW_PORT}'); \
	LANGFLOW_REDIRECT_PORT=$$(kubectl get configmap langflow-config -o jsonpath='{.data.LANGFLOW_REDIRECT_PORT}'); \
	export LANGFLOW_PORT LANGFLOW_REDIRECT_PORT; \
	nohup kubectl port-forward "$$(kubectl get pods -l app=langflow -o jsonpath='{.items[0].metadata.name}')" "$${LANGFLOW_REDIRECT_PORT}:$${LANGFLOW_PORT}" > /dev/null 2>&1 & \
	echo "Waiting for port-forward..." && sleep 5 && \
	echo "----------------- Langflow should be accessible at localhost:$${LANGFLOW_REDIRECT_PORT} -------------------"

# !!! HELPERS FOR TESTING !!!
reset-db:
	@echo "----------------- Deleting Postgres deployment to release PVC -------------------"
	-kubectl delete deployment postgres
	@echo "----------------- Deleting Postgres Persistent Volume Claim (PVC) to WIPE DATA -------------------"
	-kubectl delete pvc postgres-pvc
	@echo "Database reset. Run 'make up-k8s' to re-initialize."

logs:
	@echo "----------------- Following logs for Postgres pod -------------------"
	@kubectl logs -f $$(kubectl get pods -l app=postgres -o jsonpath='{.items[0].metadata.name}')