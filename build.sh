#!/bin/bash

set -eu

AMI_OWNER="099720109477"
REGION="ap-northeast-1"
AMI_NAME_PREFIX="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-"

TEMP_FILE=$(mktemp)

# get images
aws ec2 describe-images --owners "${AMI_OWNER}" --query 'sort_by(Images, &CreationDate)[:1]' --filters "Name=name,Values=${AMI_NAME_PREFIX}*" > "${TEMP_FILE}"

# Get snapshot-id
ORIGINAL_SNAPSHOT=$(<"${TEMP_FILE}" jq -r '.[0]["BlockDeviceMappings"][0]["Ebs"]["SnapshotId"]')
ORIGINAL_NAME=$(<"${TEMP_FILE}" jq -r '.[0]["Name"]')
ORIGINAL_DESCRIPTION=$(<"${TEMP_FILE}" jq -r '.[0]["Description"]')

# Generate new snapshot
SNAPSHOT=$(aws ec2 copy-snapshot --source-region "${REGION}" --destination-region "${REGION}" --source-snapshot-id "${ORIGINAL_SNAPSHOT}" | jq -r ".SnapshotId")

# wait for snapshot creation
while :
do
  sleep 1
  if test "$(aws ec2 describe-snapshots --snapshot-ids "${SNAPSHOT}" | jq -r '.["Snapshots"][0]["State"]')" = "completed"; then
    break
  fi
done

BLOCK_DEVICE_MAPPINGS_JSON=$(<"${TEMP_FILE}" jq --arg SNAPSHOT_ID "${SNAPSHOT}" -c '.[0]["BlockDeviceMappings"][0]["Ebs"]["SnapshotId"] = $SNAPSHOT_ID | del(.[0]["BlockDeviceMappings"][0]["Ebs"]["Encrypted"]) | .[0]["BlockDeviceMappings"]')

# Build AMI
aws ec2 register-image \
  --name "${ORIGINAL_NAME}_UEFI" \
  --architecture x86_64 \
  --description "${ORIGINAL_DESCRIPTION} UEFI" \
  --root-device-name /dev/sda1 \
  --block-device-mappings "${BLOCK_DEVICE_MAPPINGS_JSON}" \
  --ena-support \
  --sriov-net-support simple \
  --virtualization-type hvm \
  --boot-mode uefi

aws ec2 register-image \
  --name "${ORIGINAL_NAME}_TPM" \
  --architecture x86_64 \
  --description "${ORIGINAL_DESCRIPTION} TPM" \
  --root-device-name /dev/sda1 \
  --block-device-mappings "${BLOCK_DEVICE_MAPPINGS_JSON}" \
  --ena-support \
  --sriov-net-support simple \
  --virtualization-type hvm \
  --boot-mode uefi \
  --tpm-support v2.0

rm "${TEMP_FILE}"
