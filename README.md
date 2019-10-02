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

1. Create A Secret in AWS Secrets Manager. By Default the Secret is named `GuardDutyHEC` and located in `us-east-1`. The format of the secret should be:
```json
{
  "HECToken": "2SOMETHING-THAT-SHOULD-BE-SECRET",
  "HECEndpoint": "https://hec.endpoint.yourcompany.com:8088/services/collector/event"
}
```
2. Deploy it everywhere via the `deploy_splunk_to_all_regions.sh` script
```bash
~/aws-guardduty-enterprise$ ./scripts/deploy_splunk_to_all_regions.sh
```
The Script will deploy a CloudFormation Stack in each region named `GuardDuty2Splunk-$region` and wait for a successful deployment before proceeding to the next region. Modify this script if you didn't use the default secret name, secret region, or want to name the Lambda or CFT something else.

3. You can remove the stacks in each region with the `./scripts/delete_splunk_stack_in_all_regions.sh` shell script.

Note: There is no update script at the moment. Sorry.....

## Required format for the SNS Message for the Enable Lambda:
The message published to SNS must contain the following element:
```python
    message = {
        'account_id': 'string',
        'dry_run': true|false,  # optional, if un-specified, dry_run=false
        'region': ['string'],   # optional, if un-specified, runs all regions
    }
```