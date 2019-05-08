#!/usr/bin/env python3

import boto3
from botocore.exceptions import ClientError
import json
import logging
import os
import time


logger = logging.getLogger()
logger.setLevel(logging.DEBUG)
# Quiet Boto3
logging.getLogger('botocore').setLevel(logging.WARNING)
logging.getLogger('boto3').setLevel(logging.WARNING)

# Deploy Guard Duty across all child accounts to the payer account
# Process documented here:
# https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_accounts.html#guardduty_become_api


def handler(event, context):
    '''
    message = {
        'account_id': 'string',
        'dry_run': true|false,  // optional, if un-specified, dry_run=false
        'region': ['string'],  // optional, if un-specified, runs all regions
    }
    '''
    logger.debug("Received event: " + json.dumps(event, sort_keys=True))
    message = json.loads(event['Records'][0]['Sns']['Message'])
    logger.info("Received message: " + json.dumps(message, sort_keys=True))

    # account_id to operate on must be specified
    if "account_id" not in message:
        error_message = "message['account_id'] must be specified"
        logger.error(error_message)
        raise KeyError(error_message)

    # get parent organization's account_id
    message['payer_account_id'] = get_parent_organization_account_id(message)
    logger.info(f"Found payer account_id: {message['payer_account_id']}")

    # describe account (from payer account)
    message["account_info"] = describe_account(message)

    # add optional message attributes as necessary
    process_message(message)

    # process each region in the request
    for region in message['region']:
        process_region(message, region)


def process_region(event, region):
    logger.info(f"Processing Region: {region}")

    # Local client in the GD Master account
    gd_client = boto3.client('guardduty', region_name=region)
    try:
        response = gd_client.list_detectors()
        if len(response['DetectorIds']) == 0:
            # We better create one
            detector_id = create_masteraccount_detector(gd_client, event, region)
        else:
            # An account can only have one detector per region
            detector_id = response['DetectorIds'][0]
    except ClientError as e:
        logger.error("Unable to list detectors in region {}. Skipping this region.".format(region))
        return(False)
    except EndpointConnectionError as e:
        logger.error("Unable to connect to GuardDuty in region {}. Skipping this region.".format(region))
        return(False)

    gd_status = get_all_members(region, gd_client, detector_id)

    account = event['account_info']
    account_name = account['Name']
    account_id = account['Id']
    if account['Status'] != "ACTIVE":
        logger.info(f"Account {account_name}({account_id}) is inactive. No action being taken.")
        return

    if account_id not in gd_status:
        if event["dry_run"]:
            logger.info(f"Need to enable GuardDuty for {account_name}({account_id})")
        else:
            logger.info(f"Enabling GuardDuty for {account_name}({account_id})")
        if "accept_only" not in event or not event["accept_only"]:
            invite_account(account, detector_id, gd_client, event, region)
            time.sleep(3)
        accept_invite(account, os.environ['ACCEPT_ROLE'], event, region)
    elif gd_status[account_id]['RelationshipStatus'] == "Enabled":
        logger.info(f"{account_name}({account_id}) is already GuardDuty-enabled in {region}")
    else:
        logger.error(f"{account_name}({account_id}) is in unexpected GuardDuty state "
                     f"{gd_status[account_id]['RelationshipStatus']} in {region}")


def create_masteraccount_detector(gd_client, event, region):
    if event["dry_run"]:
        logger.info(f"Need to create a Detector in {region} for the GuardDuty Master account")
        return(None)

    logger.info(f"Creating a Detector in {region} for the GuardDuty Master account")
    try:
        response = gd_client.create_detector(Enable=True)
        return(response['DetectorId'])
    except ClientError as e:
        logger.error(f"Failed to create detector in {region}. Aborting...")
        raise


def get_all_members(region, gd_client, detector_id):
    output = {}
    response = gd_client.list_members(DetectorId=detector_id, MaxResults=50)
    while 'NextToken' in response:
        for a in response['Members']:
            # Convert to a lookup table
            output[a['AccountId']] = a
        response = gd_client.list_members(
            DetectorId=detector_id,
            MaxResults=50,
            NextToken=response['NextToken'],
        )
    for a in response['Members']:
        # Convert to a lookup table
        output[a['AccountId']] = a

    return(output)


def invite_account(account, detector_id, gd_client, event, region):
    if event["dry_run"]:
        logger.info(f"Need to Invite {account['Name']}({account['Id']}) to this GuardDuty Master")
        return(None)

    logger.info(f"Inviting {account['Name']}({account['Id']}) to this GuardDuty Master")
    gd_client.create_members(
        AccountDetails=[
            {
                'AccountId': account['Id'],
                'Email': account['Email'],
            },
        ],
        DetectorId=detector_id,
    )
    gd_client.invite_members(
        AccountIds=[account['Id']],
        DetectorId=detector_id,
        DisableEmailNotification=True,
    )


def accept_invite(account, role_name, event, region):
    if event["dry_run"]:
        logger.info(f"Need to accept invite in {account['Name']}({account['Id']})")
        return(None)

    logger.info(f"Accepting invite in {account['Name']}({account['Id']})")

    role_arn = create_role_arn(account['Id'], role_name)
    creds = get_creds(role_arn)

    child_client = boto3.client(
        'guardduty',
        region_name=region,
        aws_access_key_id=creds['AccessKeyId'],
        aws_secret_access_key=creds['SecretAccessKey'],
        aws_session_token=creds['SessionToken'],
    )

    response = child_client.list_detectors()
    if len(response['DetectorIds']) == 0:
        response = child_client.create_detector(Enable=True)
        detector_id = response['DetectorId']
    else:
        detector_id = response['DetectorIds'][0]

    response = child_client.list_invitations()
    for i in response['Invitations']:
        child_client.accept_invitation(
            DetectorId=detector_id,
            InvitationId=i['InvitationId'],
            MasterId=i['AccountId'],
        )


def create_role_arn(account_id, role_name):
    return f"arn:aws:iam::{account_id}:role/{role_name}"


def get_creds(role_arn):
    client = boto3.client('sts')
    try:
        session = client.assume_role(
            RoleArn=role_arn, RoleSessionName="EnableGuardDuty",
        )
        return(session['Credentials'])
    except Exception as e:
        logger.error(f"Failed to assume role {role_arn}: {e}")
        raise


def get_parent_organization_account_id(event):
    role_arn = create_role_arn(event['account_id'], os.environ['ACCEPT_ROLE'])
    creds = get_creds(role_arn)
    org_client = boto3.client(
        'organizations',
        aws_access_key_id=creds['AccessKeyId'],
        aws_secret_access_key=creds['SecretAccessKey'],
        aws_session_token=creds['SessionToken'],
    )
    response = org_client.describe_organization()
    return response['Organization']['MasterAccountId']


def describe_account(event):
    '''
    Returns: {
        'Id': 'string',
        'Arn': 'string',
        'Email': 'string',
        'Name': 'string',
        'Status': 'ACTIVE'|'SUSPENDED',
        'JoinedMethod': 'INVITED'|'CREATED',
        'JoinedTimestamp': datetime(2015, 1, 1)
    }
    '''
    role_arn = create_role_arn(event["payer_account_id"], os.environ["AUDIT_ROLE"])
    creds = get_creds(role_arn)
    org_client = boto3.client(
        'organizations',
        aws_access_key_id=creds['AccessKeyId'],
        aws_secret_access_key=creds['SecretAccessKey'],
        aws_session_token=creds['SessionToken']
    )
    try:
        response = org_client.describe_account(AccountId=event["account_id"])
        return response['Account']
    except ClientError as e:
        logger.error(
            f"Unable to get account details from Organizational Parent: {e}.\nAborting...")
        raise


def process_message(message):
    '''Add in the optional elements of the message'''

    if "dry_run" not in message:
        logger.info("message['dry_run'] not specified; default = False")
        message['dry_run'] = False

    if "region" not in message or not message["region"]:
        logger.info("message['region'] not specified; default = all regions")
        ec2 = boto3.client('ec2')
        response = ec2.describe_regions()
        message['region'] = [r['RegionName'] for r in response['Regions']]


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", help="log debugging info", action='store_true')
    parser.add_argument("--error", help="log error info only", action='store_true')

    #
    # Required
    #
    parser.add_argument("--account_id", help="AWS Account ID", required=True)
    parser.add_argument("--audit_role", help="Name of role to assume in payer account", required=True)
    parser.add_argument("--accept_role", help="Name of the role to assume in child accounts", required=True)
    parser.add_argument("--region", help="Only run in this region (list)")
    # parser.add_argument("--message", help="Custom Message sent to child as part of invite")

    parser.add_argument("--accept_only", help="Accept existing invite", action='store_true')
    parser.add_argument("--dry-run", help="Don't actually do it", action='store_true')

    args = parser.parse_args()

    # Logging idea from: https://docs.python.org/3/howto/logging.html#configuring-logging
    # create console handler and set level to debug
    ch = logging.StreamHandler()
    if args.debug:
        ch.setLevel(logging.DEBUG)
    elif args.error:
        ch.setLevel(logging.ERROR)
    else:
        ch.setLevel(logging.INFO)

    # create formatter
    formatter = logging.Formatter('%(name)s - %(levelname)s - %(message)s')
    # add formatter to ch
    ch.setFormatter(formatter)
    # add ch to logger
    logger.addHandler(ch)

    # Build the Message structure
    message = {}
    if args.account_id:
        message['account_id'] = args.account_id
    # if args.message:
    #     message['message'] = args.message
    if args.dry_run:
        message['dry_run'] = True
    if args.region:
        message['region'] = args.region

    os.environ['ACCEPT_ROLE'] = args.accept_role
    os.environ['AUDIT_ROLE'] = args.audit_role

    event = {
        'Records': [
            {
                'Sns': {
                    'Message': json.dumps(message),
                }
            }
        ]
    }
    context = {}
    handler(event, context)
