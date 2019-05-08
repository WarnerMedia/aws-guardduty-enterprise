# aws-guardduty-enterprise
Manage GuardDuty At Enterprise Scale


## What this repo does
1. Deploy a lambda to enable GuardDuty for new accounts.
2. Deploy a Lambda to take GuardDuty CloudWatch Events and forward to an Splunk HTTP Event Collector (HEC) of your choice

More stuff to come later. Like Splunk forwarding, or Security Hub. Maybe....


## Deployment of the GuardDuty Enable (and Master/Member invitation) Lambda

1. Install cfn-deploy
```bash
pip3 install cftdeploy
```
2. Make the Manifest
```bash
make BUCKET=SETME enable-manifest
```
3. Edit the Manifest
    1. Remove the lines for pLambdaZipFile and pDeployBucket as they will be set by the Makefile
    2. Add the role name for listing accounts in the payer (pAuditRole) and for accepting the invite in the child (pAcceptRole)
    3. Add a SES emailed email address for the pEmailFrom and pEmailTo parameters
    3. Replace None with the new account topic if you want to subscribe the lambda to a new account topic
4. Validate the manifest
```bash
make BUCKET=SETME enable-validate-manifest
```
5. Deploy!
```bash
make BUCKET=SETME enable-deploy
```


## Deployment of the GuardDuty To Splunk Lambdas

This is Deployed via the SAM application for Splunk logging. See the [AWS Console Page](https://console.aws.amazon.com/lambda/home?region=us-east-1#/create/app?applicationId=arn:aws:serverlessrepo:us-east-1:708419456681:applications/splunk-logging) for more info.

The makefile will deploy it to all regions

1. Install cfn-deploy
```bash
pip3 install cftdeploy
```
2. Make the Manifest
```bash
make BUCKET=SETME splunk-manifest
```
3. Edit the Manifest
    1. SET the HEC Token and URL in the Manifest
    2. Remove the region
5. Deploy to all regions
```bash
make BUCKET=SETME splunk-deploy
```



## Required format for the SNS Message for the Enable Lambda:
The message published to SNS must contain the following element:
```python
    message = {
        'account_id': 'string',
        'dry_run': true|false,  # optional, if un-specified, dry_run=false
        'region': ['string'],   # optional, if un-specified, runs all regions
    }
```