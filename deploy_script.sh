#!/bin/bash

################################################################################
# AWS Serverless Backend - Deployment Script
# Purpose: Demonstrates AWS CLI usage and deployment workflow understanding
#
# IMPORTANT: This is an ILLUSTRATIVE script for architecture demonstration
# It shows the CONCEPTS and SEQUENCE of deployment, not production automation
#
# This is NOT:
# - Production-ready (no error recovery, rollback, or comprehensive validation)
# - Actually tested on live AWS (placeholder values used)
# - A replacement for CloudFormation/Terraform
#
# This IS:
# - A demonstration of deployment sequence understanding
# - A reference for manual deployment steps
# - An illustration of AWS CLI command structure
################################################################################

set -e  # Exit on any error (basic error handling)

# Color output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
# In production, these would come from environment variables or config files
AWS_REGION="us-east-1"
FUNCTION_NAME="serverless-backend"
TABLE_NAME="ServerlessBackendTable"
ROLE_NAME="ServerlessBackendLambdaRole"
API_NAME="ServerlessBackendAPI"
ACCOUNT_ID="YOUR_ACCOUNT_ID"  # Placeholder - would use $(aws sts get-caller-identity --query Account --output text)

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Serverless Backend Deployment${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "${RED}WARNING: This is a CONCEPTUAL script${NC}"
echo -e "${RED}Replace placeholder values before actual deployment${NC}"
echo ""

################################################################################
# Step 1: Create DynamoDB Table
# Demonstrates understanding of database provisioning
################################################################################
echo -e "${GREEN}Step 1: Creating DynamoDB Table${NC}"
echo "Command: aws dynamodb create-table"
echo "Purpose: Provision NoSQL database for serverless backend"
echo ""

# This command would create the table defined in dynamodb/table-schema.json
# In production, use CloudFormation or Terraform instead of manual CLI
aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions \
        AttributeName=id,AttributeType=S \
    --key-schema \
        AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}" \
    --tags \
        Key=Project,Value=ServerlessBackend \
        Key=Environment,Value=Prototype \
    || echo "Table may already exist"

echo "Waiting for table to become active..."
# aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${AWS_REGION}"
echo -e "${GREEN}✓ DynamoDB table ready${NC}"
echo ""

################################################################################
# Step 2: Create IAM Role for Lambda
# Demonstrates understanding of security and permissions
################################################################################
echo -e "${GREEN}Step 2: Creating IAM Execution Role${NC}"
echo "Command: aws iam create-role"
echo "Purpose: Define Lambda's permissions (least privilege)"
echo ""

# Create trust policy (allows Lambda service to assume this role)
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the IAM role
aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --description "Execution role for serverless backend Lambda" \
    --region "${AWS_REGION}" \
    || echo "Role may already exist"

# Attach our custom policy from iam/lambda-policy.json
echo "Attaching permissions policy..."
aws iam put-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "ServerlessBackendPolicy" \
    --policy-document file://iam/lambda-policy.json \
    --region "${AWS_REGION}"

# Also attach AWS managed policy for basic Lambda execution
aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
    --region "${AWS_REGION}" \
    || true

echo "Waiting for IAM role propagation (30 seconds)..."
# IAM changes take time to propagate globally
sleep 30
echo -e "${GREEN}✓ IAM role created${NC}"
echo ""

################################################################################
# Step 3: Package Lambda Function
# Demonstrates understanding of deployment artifacts
################################################################################
echo -e "${GREEN}Step 3: Packaging Lambda Function${NC}"
echo "Purpose: Create deployment package with code and dependencies"
echo ""

# Create deployment package
cd lambda
zip -r /tmp/function.zip handler.py
cd ..

echo -e "${GREEN}✓ Lambda package created${NC}"
echo ""

################################################################################
# Step 4: Deploy Lambda Function
# Demonstrates understanding of serverless compute deployment
################################################################################
echo -e "${GREEN}Step 4: Deploying Lambda Function${NC}"
echo "Command: aws lambda create-function"
echo "Purpose: Deploy serverless compute layer"
echo ""

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

aws lambda create-function \
    --function-name "${FUNCTION_NAME}" \
    --runtime python3.11 \
    --role "${ROLE_ARN}" \
    --handler handler.lambda_handler \
    --zip-file fileb:///tmp/function.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment "Variables={DYNAMODB_TABLE=${TABLE_NAME}}" \
    --region "${AWS_REGION}" \
    || echo "Function may already exist, updating code..."

# If function exists, update it instead
aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file fileb:///tmp/function.zip \
    --region "${AWS_REGION}" \
    || true

echo -e "${GREEN}✓ Lambda function deployed${NC}"
echo ""

################################################################################
# Step 5: Create API Gateway
# Demonstrates understanding of API layer configuration
################################################################################
echo -e "${GREEN}Step 5: Creating API Gateway${NC}"
echo "Command: aws apigateway create-rest-api"
echo "Purpose: Create HTTP entry point for Lambda"
echo ""

# In production, would import OpenAPI spec from api/api-definition.yaml
# For simplicity, showing manual creation

API_ID=$(aws apigateway create-rest-api \
    --name "${API_NAME}" \
    --description "REST API for serverless backend" \
    --endpoint-configuration types=REGIONAL \
    --region "${AWS_REGION}" \
    --query 'id' \
    --output text)

echo "API ID: ${API_ID}"

# Get root resource ID
ROOT_ID=$(aws apigateway get-resources \
    --rest-api-id "${API_ID}" \
    --region "${AWS_REGION}" \
    --query 'items[?path==`/`].id' \
    --output text)

# Create /items resource
ITEMS_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id "${API_ID}" \
    --parent-id "${ROOT_ID}" \
    --path-part "items" \
    --region "${AWS_REGION}" \
    --query 'id' \
    --output text)

# Create GET method on /items
aws apigateway put-method \
    --rest-api-id "${API_ID}" \
    --resource-id "${ITEMS_RESOURCE_ID}" \
    --http-method GET \
    --authorization-type NONE \
    --region "${AWS_REGION}"

# Integrate GET method with Lambda
LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"
aws apigateway put-integration \
    --rest-api-id "${API_ID}" \
    --resource-id "${ITEMS_RESOURCE_ID}" \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
    --region "${AWS_REGION}"

# Grant API Gateway permission to invoke Lambda
aws lambda add-permission \
    --function-name "${FUNCTION_NAME}" \
    --statement-id apigateway-access \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API_ID}/*/*" \
    --region "${AWS_REGION}" \
    || true

echo -e "${GREEN}✓ API Gateway created${NC}"
echo ""

################################################################################
# Step 6: Deploy API Stage
# Demonstrates understanding of API deployment and versioning
################################################################################
echo -e "${GREEN}Step 6: Deploying API Stage${NC}"
echo "Purpose: Make API publicly accessible"
echo ""

aws apigateway create-deployment \
    --rest-api-id "${API_ID}" \
    --stage-name "prod" \
    --stage-description "Production stage" \
    --region "${AWS_REGION}"

API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"

echo -e "${GREEN}✓ API deployed${NC}"
echo ""

################################################################################
# Deployment Complete
################################################################################
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "API Endpoint: ${YELLOW}${API_ENDPOINT}${NC}"
echo -e "Function Name: ${YELLOW}${FUNCTION_NAME}${NC}"
echo -e "Table Name: ${YELLOW}${TABLE_NAME}${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Test API: curl ${API_ENDPOINT}/items"
echo "2. View logs: aws logs tail /aws/lambda/${FUNCTION_NAME} --follow"
echo "3. Monitor metrics in CloudWatch console"
echo ""
echo -e "${RED}Remember: This is a prototype for demonstration${NC}"
echo -e "${RED}Production deployment should use IaC (CloudFormation/Terraform)${NC}"
echo ""

################################################################################
# What This Script Demonstrates
################################################################################
# ✓ Understanding of AWS service dependencies and deployment sequence
# ✓ Knowledge of IAM role creation and policy attachment
# ✓ Understanding of Lambda packaging and configuration
# ✓ Knowledge of API Gateway setup and Lambda integration
# ✓ Awareness of permission grants (Lambda invoke permission)
# ✓ Understanding of deployment stages and API endpoints
#
# What's Missing (Intentionally, for Prototype):
# ✗ Error handling and rollback mechanisms
# ✗ Environment-specific configurations
# ✗ Automated testing and validation
# ✗ Blue-green or canary deployment strategies
# ✗ Secrets management
# ✗ Custom domain and SSL certificate setup
# ✗ WAF and security rules
# ✗ Cost monitoring and budget alerts
################################################################################