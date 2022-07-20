#!/bin/bash

set -eu

AMI_OWNER="099720109477"
REGION="ap-northeast-1"
AMI_NAME_PREFIX="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-"

TEMP_FILE=$(mktemp)

# get images
aws ec2 describe-images --owners "${AMI_OWNER}" --query 'sort_by(Images, &CreationDate)[-1]' --filters "Name=name,Values=${AMI_NAME_PREFIX}*" > "${TEMP_FILE}"

# Get snapshot-id
ORIGINAL_SNAPSHOT=$(<"${TEMP_FILE}" jq -r '.["BlockDeviceMappings"][0]["Ebs"]["SnapshotId"]')
ORIGINAL_NAME=$(<"${TEMP_FILE}" jq -r '.["Name"]')
ORIGINAL_DESCRIPTION=$(<"${TEMP_FILE}" jq -r '.["Description"]')

# check availability of current ami
UEFI_AMI=$(aws ec2 describe-images --owners self --filters "Name=name,Values=UEFI_${ORIGINAL_NAME}" --query "Images[0].ImageId" --output text)
TPM_AMI=$(aws ec2 describe-images --owners self --filters "Name=name,Values=TPM_${ORIGINAL_NAME}" --query "Images[0].ImageId" --output text)

if test "${UEFI_AMI}" != "None" -a "${TPM_AMI}" != "None"; then
  exit 0
fi

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

BLOCK_DEVICE_MAPPINGS_JSON=$(<"${TEMP_FILE}" jq --arg SNAPSHOT_ID "${SNAPSHOT}" -c '.["BlockDeviceMappings"][0]["Ebs"]["SnapshotId"] = $SNAPSHOT_ID | del(.["BlockDeviceMappings"][0]["Ebs"]["Encrypted"]) | .["BlockDeviceMappings"]')

# Build AMI
if test "${UEFI_AMI}" = "None"; then
  aws ec2 register-image \
    --name "UEFI_${ORIGINAL_NAME}" \
    --architecture x86_64 \
    --description "${ORIGINAL_DESCRIPTION} UEFI" \
    --root-device-name /dev/sda1 \
    --block-device-mappings "${BLOCK_DEVICE_MAPPINGS_JSON}" \
    --ena-support \
    --sriov-net-support simple \
    --virtualization-type hvm \
    --boot-mode uefi
fi

if test "${TPM_AMI}" = "None"; then
  aws ec2 register-image \
    --name "TPM_${ORIGINAL_NAME}" \
    --architecture x86_64 \
    --description "${ORIGINAL_DESCRIPTION} TPM" \
    --root-device-name /dev/sda1 \
    --block-device-mappings "${BLOCK_DEVICE_MAPPINGS_JSON}" \
    --ena-support \
    --sriov-net-support simple \
    --virtualization-type hvm \
    --boot-mode uefi \
    --tpm-support v2.0
fi

rm "${TEMP_FILE}"
