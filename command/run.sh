#!/usr/bin/env bash

function usage()
{
    echo "  -h --help"
    echo "  -c --command=<command>"
    echo "  -r --region=<region-name>"
    echo "  -g --logGroupName=<log-group-name>"
    echo ""
}

COMMAND=""
REGION_NAME=""
GROUP_NAME="k8s"

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case ${PARAM} in
        -h | --help)
            usage
            exit
            ;;
        -c | --command)
            COMMAND=${VALUE}
            ;;
        -r | --region)
            REGION_NAME=${VALUE}
            ;;
        -g | --groupName)
            GROUP_NAME=${VALUE}
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$COMMAND" ]; then
    echo "command is required"
    usage
    exit 1
fi

if [ -z "$REGION_NAME" ]; then
    echo "region name is required"
    usage
    exit 1
fi

COMMAND=(${COMMAND[@]})
SIZE=${#COMMAND[@]}
INDEX=0
CONCAT=""
while [ "$INDEX" != "$SIZE" ]; do
    CONCAT=$(echo "${CONCAT} \"$(printf '%q' ${COMMAND[INDEX]})\"")
    INDEX=$(($INDEX + 1))
    if [ "$INDEX" != "$SIZE" ]; then
        CONCAT="$CONCAT ,"
    fi
done
echo ${CONCAT}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ORIGINAL=${DIR}/kafka-command.yml
TEMP=${ORIGINAL}.temp

cp ${ORIGINAL} ${TEMP}

echo "run command: $CONCAT"
sed -i -e "s@{{COMMAND}}@$(printf '%q' ${CONCAT})@g" "${TEMP}"

kubectl create -f ${TEMP}
rm ${TEMP}

kubectl describe jobs/kafka-command --namespace kafka-command

STATUS="Pending"
POD_NAME=""

TIMEOUT=15
while [ "$STATUS" != "Succeeded" ]; do
    sleep 1

    PODS=$(kubectl get pods --namespace kafka-command --show-all -o=json)

    if [ -z "$POD_NAME" ]; then
        echo "getting pod name..."
        POD_NAME=$(echo ${PODS} | jq --raw-output '.items[] | select(.metadata.labels."job-name"=="kafka-command" and (.status.phase=="Pending" or .status.phase=="Succeeded")) | .metadata.name')
        if [ -z "$POD_NAME" ]; then
            continue
        else
            echo "pod name: $POD_NAME"
        fi
    fi

    STATUS=$(echo ${PODS} | jq --raw-output ".items[] | select(.metadata.labels.\"job-name\"==\"kafka-command\" and .metadata.name == \"${POD_NAME}\") | .status.phase")
    echo ${STATUS}
    TIMEOUT=$(($TIMEOUT - 1))
    if [ "$TIMEOUT" == "0" ]; then
        break
    fi
    if [ "$STATUS" == "Failed" ]; then
        break
    fi
done

CONTAINER_ID=$(echo ${PODS} | jq --raw-output ".items[] | select(.metadata.labels.\"job-name\"==\"kafka-command\" and .metadata.name == \"${POD_NAME}\") | .status.containerStatuses[].containerID")
CONTAINER_ID=${CONTAINER_ID:9}

echo "output:"
aws logs get-log-events --log-group-name ${GROUP_NAME} --log-stream-name ${CONTAINER_ID} --region ${REGION_NAME} | jq --raw-output ".events[].message"

kubectl delete namespace kafka-command
