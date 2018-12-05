# Customize these Settings
export DEPLOYBUCKET ?= FIXME

ifndef env
	env ?= dev
endif

ifndef version
	export version := $(shell date +%Y%b%d-%H%M)
endif

# Shouldn't be overridden
export AWS_LAMBDA_FUNCTION_PREFIX ?= aws-guardduty-enterprise
export AWS_TEMPLATE ?= cloudformation/GuardDuty-Template.yaml
export LAMBDA_PACKAGE ?= lambda-$(version).zip
export manifest ?= cloudformation/GuardDuty-Manifest-$(env).yaml
export AWS_LAMBDA_FUNCTION_NAME=$(AWS_LAMBDA_FUNCTION_PREFIX)-$(env)
export OBJECT_KEY ?= $(AWS_LAMBDA_FUNCTION_PREFIX)/$(LAMBDA_PACKAGE)

FUNCTIONS = $(AWS_LAMBDA_FUNCTION_NAME)-enable-guardduty

.PHONY: $(FUNCTIONS)

# Run all tests
test: cfn-validate
	cd lambda && $(MAKE) test

deploy: package upload cfn-deploy

clean:
	cd lambda && $(MAKE) clean

#
# Cloudformation Targets
#

# Validate the template
cfn-validate: $(AWS_TEMPLATE)
	aws cloudformation validate-template --region us-east-1 --template-body file://$(AWS_TEMPLATE)

# Deploy the stack
cfn-deploy: cfn-validate $(manifest)
	deploy_stack.rb -m $(manifest) pLambdaZipFile=$(OBJECT_KEY) pDeployBucket=$(DEPLOYBUCKET) pEnvironment=$(env)  --force

#
# Lambda Targets
#
package:
	cd lambda && $(MAKE) package

upload:
	aws s3 cp lambda/$(LAMBDA_PACKAGE) s3://$(DEPLOYBUCKET)/$(OBJECT_KEY)

# Update the Lambda Code without modifying the CF Stack
update: package $(FUNCTIONS)
	for f in $(FUNCTIONS) ; do \
	  aws lambda update-function-code --function-name $$f --zip-file fileb://lambda/$(LAMBDA_PACKAGE) ; \
	done

# Update a specific Lambda function
fupdate: package
	aws lambda update-function-code --function-name $(function) --zip-file fileb://lambda/$(LAMBDA_PACKAGE) ; \
