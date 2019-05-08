

ifndef BUCKET
$(error BUCKET is not set)
endif

ifndef version
	export version := $(shell date +%Y%b%d-%H%M)
endif

# Specific to this stack
export FULL_STACK_NAME=GuardDuty-Enable
# Filename for the CFT to deploy
export STACK_TEMPLATE=cloudformation/GuardDuty-Enable-Template.yaml

# Name of the Zip file with all the function code and dependencies
export LAMBDA_PACKAGE=$(FULL_STACK_NAME)-lambda-$(version).zip

# Name of the manifest file.
export manifest=cloudformation/$(FULL_STACK_NAME)-Manifest.yaml

# location in the Antiope bucket where we drop lambda-packages
export OBJECT_KEY=deploy-packages/$(LAMBDA_PACKAGE)


# List of all the functions deployed by this stack. Required for "make update" to work.
FUNCTIONS = $(FULL_STACK_NAME)-enable-guardduty

.PHONY: $(FUNCTIONS)

# Run all tests
test: cfn-validate
	cd lambda && $(MAKE) test

# Do everything
deploy: package upload cfn-deploy

clean:
	cd lambda && $(MAKE) clean

#
# Cloudformation Targets
#

# target to generate a manifest file. Only do this once
manifest:
	cft-generate-manifest -t $(STACK_TEMPLATE) -m $(manifest) --stack-name $(FULL_STACK_NAME) --region $(AWS_DEFAULT_REGION)

# Validate the template
cfn-validate: $(STACK_TEMPLATE)
	cft-validate --region $(AWS_DEFAULT_REGION) -t $(STACK_TEMPLATE)

cfn-validate-manifest: cfn-validate
	cft-validate-manifest --region $(AWS_DEFAULT_REGION) -m $(manifest) pLambdaZipFile=$(OBJECT_KEY) pDeployBucket=$(BUCKET)

# Deploy the stack
cfn-deploy: cfn-validate $(manifest)
	cft-deploy -m $(manifest)  pLambdaZipFile=$(OBJECT_KEY) pDeployBucket=$(BUCKET)  --force

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
