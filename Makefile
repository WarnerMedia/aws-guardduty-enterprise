

ifndef BUCKET
$(error BUCKET is not set)
endif

ifndef version
	export version := $(shell date +%Y%b%d-%H%M)
endif

# Specific to this stack
export ENABLE_STACK_NAME ?= GuardDuty-Enable
export SPLUNK_STACK_NAME ?= GuardDuty2Splunk

# Filename for the CFT to deploy
export ENABLE_STACK_TEMPLATE=cloudformation/GuardDuty-Enable-Template.yaml
export SPLUNK_STACK_TEMPLATE=cloudformation/GuardDuty2Splunk-Template.yaml


# Name of the Zip file with all the function code and dependencies
export LAMBDA_PACKAGE=$(ENABLE_STACK_NAME)-lambda-$(version).zip

# Name of the manifest file.
export ENABLE_MANIFEST=cloudformation/$(ENABLE_STACK_NAME)-Manifest.yaml
export SPLUNK_MANIFEST=cloudformation/$(SPLUNK_STACK_NAME)-Manifest.yaml

# location in the Antiope bucket where we drop lambda-packages
export OBJECT_KEY=deploy-packages/$(LAMBDA_PACKAGE)


# List of all the functions deployed by this stack. Required for "make update" to work.
FUNCTIONS = $(ENABLE_STACK_NAME)-enable-guardduty

.PHONY: $(FUNCTIONS)

# Run all tests
test: cfn-validate
	cd lambda && $(MAKE) test

# Do everything
enable-deploy: package upload enable-cfn-deploy

clean:
	cd lambda && $(MAKE) clean

#
# Cloudformation Targets
#

# target to generate a manifest file. Only do this once
enable-manifest:
	cft-generate-manifest -t $(ENABLE_STACK_TEMPLATE) -m $(ENABLE_MANIFEST) --stack-name $(ENABLE_STACK_NAME) --region $(AWS_DEFAULT_REGION)



# Validate the template
cfn-validate: $(ENABLE_STACK_TEMPLATE) $(SPLUNK_STACK_TEMPLATE)
	cft-validate --region $(AWS_DEFAULT_REGION) -t $(ENABLE_STACK_TEMPLATE)
	cft-validate --region $(AWS_DEFAULT_REGION) -t $(SPLUNK_STACK_TEMPLATE)


# Enable Lambda Stack Targets

enable-validate-manifest: cfn-validate
	cft-validate-manifest --region $(AWS_DEFAULT_REGION) -m $(ENABLE_MANIFEST) pLambdaZipFile=$(OBJECT_KEY) pDeployBucket=$(BUCKET)

# Deploy the stack
enable-cfn-deploy: cfn-validate $(ENABLE_MANIFEST)
	cft-deploy -m $(ENABLE_MANIFEST)  pLambdaZipFile=$(OBJECT_KEY) pDeployBucket=$(BUCKET)  --force

#
# Splunk Deploy Stack Target
#
splunk-manifest:
	cft-generate-manifest -t $(SPLUNK_STACK_TEMPLATE) -m $(SPLUNK_MANIFEST) --stack-name $(SPLUNK_STACK_NAME)

splunk-deploy: cfn-validate $(SPLUNK_MANIFEST)
	$(eval REGIONS := $(shell aws ec2 describe-regions --output text | awk '{print $$NF}'))
	for r in $(REGIONS) ; do \
	  cft-deploy -m $(SPLUNK_MANIFEST)  --override-region $$r  --force ; \
	done



#
# Lambda Targets
#
package:
	cd lambda && $(MAKE) package

zipfile:
	cd lambda && $(MAKE) zipfile

upload: package
	aws s3 cp lambda/$(LAMBDA_PACKAGE) s3://$(BUCKET)/$(OBJECT_KEY)

# # Update the Lambda Code without modifying the CF Stack
update: package $(FUNCTIONS)
	for f in $(FUNCTIONS) ; do \
	  aws lambda update-function-code --function-name $$f --zip-file fileb://lambda/$(LAMBDA_PACKAGE) ; \
	done

# Update one specific function. Called as "make fupdate function=<fillinstackprefix>-aws-inventory-ecs-inventory"
fupdate: zipfile
	aws lambda update-function-code --function-name $(function) --zip-file fileb://lambda/$(LAMBDA_PACKAGE) ; \














# # Shouldn't be overridden
# export AWS_LAMBDA_FUNCTION_PREFIX ?= aws-guardduty-enterprise
# export AWS_TEMPLATE ?= cloudformation/GuardDuty-Template.yaml
# export LAMBDA_PACKAGE ?= lambda-$(version).zip
# export manifest ?= cloudformation/GuardDuty-Manifest-$(env).yaml
# export AWS_LAMBDA_FUNCTION_NAME=$(AWS_LAMBDA_FUNCTION_PREFIX)-$(env)
# export OBJECT_KEY ?= $(AWS_LAMBDA_FUNCTION_PREFIX)/$(LAMBDA_PACKAGE)

# FUNCTIONS = $(AWS_LAMBDA_FUNCTION_NAME)-enable-guardduty

# .PHONY: $(FUNCTIONS)

# # Run all tests
# test: cfn-validate
# 	cd lambda && $(MAKE) test

# deploy: package upload cfn-deploy

# clean:
# 	cd lambda && $(MAKE) clean

# #
# # Cloudformation Targets
# #

# # Validate the template
# cfn-validate: $(AWS_TEMPLATE)
# 	aws cloudformation validate-template --region us-east-1 --template-body file://$(AWS_TEMPLATE)

# # Deploy the stack
# cfn-deploy: cfn-validate $(manifest)
# 	deploy_stack.rb -m $(manifest) pLambdaZipFile=$(OBJECT_KEY) pDeployBucket=$(DEPLOYBUCKET) pEnvironment=$(env)  --force

# #
# # Lambda Targets
# #
# package:
# 	cd lambda && $(MAKE) package

# upload:
# 	aws s3 cp lambda/$(LAMBDA_PACKAGE) s3://$(DEPLOYBUCKET)/$(OBJECT_KEY)

# # Update the Lambda Code without modifying the CF Stack
# update: package $(FUNCTIONS)
# 	for f in $(FUNCTIONS) ; do \
# 	  aws lambda update-function-code --function-name $$f --zip-file fileb://lambda/$(LAMBDA_PACKAGE) ; \
# 	done

# # Update a specific Lambda function
# fupdate: package
# 	aws lambda update-function-code --function-name $(function) --zip-file fileb://lambda/$(LAMBDA_PACKAGE) ; \
