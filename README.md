# aws-guardduty-enterprise
Manage GuardDuty At Enterprise Scale


## What this repo does
1. Deploy a lambda to enable GuardDuty for new accounts.

More stuff to come later. Like Splunk forwarding, or Security Hub. Maybe....


## Deployment

1. Install cfn-deploy
```bash
pip3 install cftdeploy
```
2. Make the Manifest
```bash
make BUCKET=SETME manifest
```
3. Edit the Manifest
    1. Remove the lines for pLambdaZipFile and pDeployBucket as they will be set by the Makefile
    2. Add the role name for listing accounts in the payer (pAuditRole) and for accepting the invite in the child (pAcceptRole)
    3. Add a SES emailed email address for the pEmailFrom and pEmailTo parameters
    3. Replace None with the new account topic if you want to subscribe the lambda to a new account topic
4. Validate the manifest
```bash
make BUCKET=SETME cfn-validate-manifest
```
5. Deploy!
```bash
make BUCKET=SETME deploy
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