#!/bin/bash
set -e

GCS_BUCKET=gs://cromwell-perf-test/

VAULT_TOKEN=$(cat /etc/vault-token-dsde)

DOCKER_ETC_PATH=/usr/share/etc

mkdir -p mnt

DB_PASS=`docker run --rm -e VAULT_TOKEN=$VAULT_TOKEN \
	broadinstitute/dsde-toolbox vault read -format=json secret/dsp/cromwell/perf | jq '.data.db_pass'`

docker run --rm -e VAULT_TOKEN=$VAULT_TOKEN broadinstitute/dsde-toolbox vault read -format=json secret/dsp/cromwell/perf/service-account-deployer | jq -r '.data.service_account' > mnt/sa.json
	
function join() { local IFS=","; echo "$*"; }

metadata=(
  "BUILD_NUMBER=$BUILD_NUMBER"
  "BUILD_TAG=$BUILD_TAG"
  "CLEAN_UP=$CLEAN_UP"
  "CLOUD_SQL_INSTANCE=$CLOUD_SQL_INSTANCE"
  "CROMWELL_DB_USER=cromwell"
  "CROMWELL_DB_PASS=$DB_PASS"
  "CROMWELL_DOCKER_IMAGE=$CROMWELL_DOCKER_IMAGE"
  "CROMWELL_PROJECT=broad-dsde-cromwell-perf"
  "CROMWELL_BUCKET=$GCS_BUCKET"
  "CROMWELL_STATSD_HOST=10.128.0.4"
  "CROMWELL_STATSD_PORT=8125"
  "CROMWELL_PERF_SCRIPTS_BRANCH=${REPO_BRANCH}"
)

cp scripts/perf/deploy_instance/run_on_instance.sh mnt/

docker run --name perf_gcloud_$BUILD_NUMBER -v "$(pwd)"/mnt:$DOCKER_ETC_PATH --rm google/cloud-sdk:slim /bin/bash -c "\
  gcloud auth activate-service-account --key-file $DOCKER_ETC_PATH/sa.json &&\
  gcloud \
    --verbosity info \
    --project broad-dsde-cromwell-perf \
    compute \
    instances \
    create $BUILD_TAG \
    --zone us-central1-c \
    --source-instance-template $INSTANCE_TEMPLATE \
    --metadata-from-file startup-script=$DOCKER_ETC_PATH/run_on_instance.sh \
    --metadata \
        $(join ${metadata[@]})" | tee dockerResult.txt

typeset CROMWELL_UNDER_TEST=$(cat dockerResult.txt | tail -n1 | awk '{print $5}' )

echo "Determined that CROMWELL_UNDER_TEST=${CROMWELL_UNDER_TEST}"

source scripts/perf/helper.inc.sh

cd ~/
mkdir test
cd test
pwd
wait_for_cromwell
