#! /bin/bash

set -o errexit	# Bail out on errors

if [ "$#" -ne 5 ]; then
        echo "ERROR: Illegal number of parameters."
        echo "Syntax:  eos-storage-fst.sh <fst_number> <eos_mgm_alias> <eos_mq_alias> <geotag> <scheduling_group>"
        echo "Example: eos-storage-fst.sh 1 eos-mgm.eos-mgm.boxed.svc.cluster.local eos-mq.eos-mq.boxed.svc.cluster.local docker default"
        exit 1
fi


FST_BASENAME="eos-fst"
FST_NUMBER=$1
FST_NAME=${FST_BASENAME}${FST_NUMBER}
FST_CONTAINER_NAME=`echo ${FST_BASENAME} | tr '[:lower:]' '[:upper:]'`${FST_NUMBER}
MGM_ALIAS=$2
MQ_ALIAS=$3
GEOTAG=$4
SCHEDULING_GROUP=$5

FNAME="eos-storage-fst${FST_NUMBER}.yaml"
cp eos-storage-fst.template.yaml $FNAME
sed -i "s/%%%FST_NAME%%%/"${FST_NAME}"/" $FNAME
sed -i "s/%%%FST_NUMBER%%%/${FST_NUMBER}/" $FNAME
sed -i "s/%%%FST_CONTAINER_NAME%%%/${FST_CONTAINER_NAME}/" $FNAME
sed -i "s/%%%MGM_ALIAS%%%/${MGM_ALIAS}/" $FNAME
sed -i "s/%%%MQ_ALIAS%%%/${MQ_ALIAS}/" $FNAME
sed -i "s/%%%FST_GEOTAG%%%/${GEOTAG}/" $FNAME
sed -i "s/%%%FST_SCHEDULING_GROUP%%%/${SCHEDULING_GROUP}/" $FNAME

