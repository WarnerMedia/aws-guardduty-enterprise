#!/bin/bash

# All stacks will be named "${STACK_NAME}-${region}"
STACK_NAME="GuardDuty2Splunk"

# Get a list of the active AWS Regions for the account
REGIONS=`aws ec2 describe-regions --query "Regions[].RegionName" --output text`

for r in $REGIONS ; do
    echo "Deleting GuardDuty To Splunk CFT in $r"
    aws cloudformation update-termination-protection --region $r --stack-name "${STACK_NAME}-${r}" --no-enable-termination-protection
    aws cloudformation delete-stack --region $r --stack-name "${STACK_NAME}-${r}"
done