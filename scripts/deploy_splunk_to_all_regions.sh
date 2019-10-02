#!/bin/bash

# All stacks will be named "${STACK_NAME}-${region}"
STACK_NAME="GuardDuty2Splunk"

# Name of Secrets Manager secret
SECRET_NAME=GuardDutyHEC
SECRET_REGION=us-east-1



echo "Using ${SECRET_NAME} in ${SECRET_REGION} as the HEC Endpoint and Token"

# Get a list of the active AWS Regions for the account
REGIONS=`aws ec2 describe-regions --query "Regions[].RegionName" --output text`

for r in $REGIONS ; do
    echo "Deploying GuardDuty To Splunk CFT in $r"
    echo -n "New Stack ID: "
    aws cloudformation create-stack --region $r --stack-name "${STACK_NAME}-${r}" \
        --template-body file://cloudformation/GuardDuty2Splunk-Template.yaml \
        --parameters ParameterKey=pHECSecretName,ParameterValue=${SECRET_NAME} ParameterKey=pHECSecretRegion,ParameterValue=${SECRET_REGION} \
        --capabilities "CAPABILITY_IAM" \
        --enable-termination-protection --output text && \
    aws cloudformation wait stack-create-complete --region $r --stack-name "${STACK_NAME}-${r}"
    if [ $? -ne 0 ] ; then
        echo "WARNING! Failed to Deploy in $r"
    else
        echo "Successfuly deployed to $r"
    fi
done