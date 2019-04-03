#!/bin/bash
set -e

DOCKER_REPO=$1
COMMIT=$2
PUSH_MIRZA=$3

SCS_DOCKER_IMAGE_TAG="${DOCKER_REPO}/supplychainserver:$COMMIT"
BR_DOCKER_IMAGE_TAG="${DOCKER_REPO}/businessregistry:$COMMIT"
HSBUILDER_DOCKER_IMAGE="${DOCKER_REPO}/hsbuilder"
HSBUILDER_DOCKER_IMAGE_TAG="${HSBUILDER_DOCKER_IMAGE}:$(./deploy/dephash.sh)"

DATE=$(date '+%Y%m%d-%H%M')

# Install the awscli tool and add it to PATH
pip install --user awscli
export PATH=$PATH:$HOME/.local/bin

# Authenticate with AWS and push the docker images so that they can be deployed to the server
set +x # hide output
eval $(aws ecr get-login --no-include-email --region ap-southeast-2)
set -x

cd "$(dirname "$0")/../projects/br_scs"

if docker pull "${HSBUILDER_DOCKER_IMAGE_TAG}"; then
	echo "Skipping, ${HSBUILDER_DOCKER_IMAGE_TAG} already exists..."
else
	docker build -f HsBuilder.Dockerfile -t "${HSBUILDER_DOCKER_IMAGE}:latest" -t "${HSBUILDER_DOCKER_IMAGE_TAG}" -t "${HSBUILDER_DOCKER_IMAGE}:${DATE}" .
	docker push "${HSBUILDER_DOCKER_IMAGE_TAG}"
fi

docker build -f Mirza.Dockerfile --target PKG-SCS --build-arg HS_BUILDER_IMAGE="${HSBUILDER_DOCKER_IMAGE_TAG}" -t "${SCS_DOCKER_IMAGE_TAG}" .
docker build -f Mirza.Dockerfile --target PKG-BR --build-arg HS_BUILDER_IMAGE="${HSBUILDER_DOCKER_IMAGE_TAG}" -t "${BR_DOCKER_IMAGE_TAG}" .

if [ "$PUSH_MIRZA" ]; then
    docker push "${SCS_DOCKER_IMAGE_TAG}"
    docker push "${BR_DOCKER_IMAGE_TAG}"
fi