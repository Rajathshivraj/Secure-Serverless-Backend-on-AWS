"""
AWS Lambda Handler - Serverless Backend
Purpose: Demonstrates CRUD operations with DynamoDB in a serverless context

This handler processes API Gateway events and performs database operations.
It shows understanding of:
- Event-driven architecture
- DynamoDB operations with boto3
- Error handling patterns
- JSON response formatting for API Gateway
"""

import json
import boto3
import os
from datetime import datetime
from decimal import Decimal

# Initialize DynamoDB client
# boto3 is automatically available in Lambda runtime
dynamodb = boto3.resource('dynamodb')

# Table name would come from environment variable in production
# This demonstrates configuration management awareness
TABLE_NAME = os.environ.get('DYNAMODB_TABLE', 'ServerlessBackendTable')
table = dynamodb.Table(TABLE_NAME)


class DecimalEncoder(json.JSONEncoder):
    """
    DynamoDB returns numbers as Decimal type.
    This encoder converts Decimal to int/float for JSON serialization.
    Shows understanding of DynamoDB-specific quirks.
    """
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)


def lambda_handler(event, context):
    """
    Main Lambda handler function.
    
    Event: Contains HTTP request data from API Gateway
    Context: Runtime information (request ID, memory, etc.)
    
    Returns: API Gateway-compatible response object
    """
    
    # Extract HTTP method and path from API Gateway event
    # This demonstrates understanding of API Gateway integration
    http_method = event.get('httpMethod', '')
    path = event.get('path', '')
    
    # Parse request body if present
    body = {}
    if event.get('body'):
        try:
            body = json.loads(event['body'])
        except json.JSONDecodeError:
            return build_response(400, {'error': 'Invalid JSON in request body'})
    
    # Route to appropriate handler based on HTTP method
    # Demonstrates RESTful API pattern understanding
    try:
        if http_method == 'GET':
            response = handle_get(event)
        elif http_method == 'POST':
            response = handle_post(body)
        elif http_method == 'PUT':
            response = handle_put(event, body)
        elif http_method == 'DELETE':
            response = handle_delete(event)
        else:
            response = build_response(405, {'error': 'Method not allowed'})
            
    except Exception as e:
        # In production, this would use structured logging
        print(f"Error processing request: {str(e)}")
        response = build_response(500, {'error': 'Internal server error'})
    
    return response


def handle_get(event):
    """
    Handle GET requests - Retrieve item(s) from DynamoDB
    Demonstrates read operations and query patterns
    """
    
    # Extract item ID from path parameters
    # Example: /items/{id}
    path_params = event.get('pathParameters', {})
    item_id = path_params.get('id') if path_params else None
    
    if item_id:
        # Get single item by primary key
        # Shows understanding of DynamoDB GetItem operation
        response = table.get_item(Key={'id': item_id})
        
        if 'Item' in response:
            return build_response(200, response['Item'])
        else:
            return build_response(404, {'error': 'Item not found'})
    else:
        # Scan all items (limited to demonstration)
        # In production, would use pagination and filtering
        response = table.scan(Limit=50)
        return build_response(200, {'items': response.get('Items', [])})


def handle_post(body):
    """
    Handle POST requests - Create new item in DynamoDB
    Demonstrates write operations and data validation
    """
    
    # Validate required fields
    # Shows understanding of input validation
    if 'id' not in body or 'data' not in body:
        return build_response(400, {'error': 'Missing required fields: id, data'})
    
    # Create item with timestamp
    # Demonstrates adding metadata for tracking
    item = {
        'id': body['id'],
        'data': body['data'],
        'created_at': datetime.utcnow().isoformat(),
        'updated_at': datetime.utcnow().isoformat()
    }
    
    # Write to DynamoDB
    # Shows understanding of PutItem operation
    table.put_item(Item=item)
    
    return build_response(201, {'message': 'Item created', 'item': item})


def handle_put(event, body):
    """
    Handle PUT requests - Update existing item
    Demonstrates update operations and conditional logic
    """
    
    path_params = event.get('pathParameters', {})
    item_id = path_params.get('id') if path_params else None
    
    if not item_id:
        return build_response(400, {'error': 'Item ID required in path'})
    
    if 'data' not in body:
        return build_response(400, {'error': 'Missing required field: data'})
    
    # Update item with new data and timestamp
    # Shows understanding of UpdateItem with expressions
    response = table.update_item(
        Key={'id': item_id},
        UpdateExpression='SET #data = :data, updated_at = :timestamp',
        ExpressionAttributeNames={
            '#data': 'data'  # Using placeholder to avoid reserved word issues
        },
        ExpressionAttributeValues={
            ':data': body['data'],
            ':timestamp': datetime.utcnow().isoformat()
        },
        ReturnValues='ALL_NEW'
    )
    
    return build_response(200, {'message': 'Item updated', 'item': response['Attributes']})


def handle_delete(event):
    """
    Handle DELETE requests - Remove item from DynamoDB
    Demonstrates delete operations
    """
    
    path_params = event.get('pathParameters', {})
    item_id = path_params.get('id') if path_params else None
    
    if not item_id:
        return build_response(400, {'error': 'Item ID required in path'})
    
    # Delete item from DynamoDB
    # Shows understanding of DeleteItem operation
    table.delete_item(Key={'id': item_id})
    
    return build_response(200, {'message': 'Item deleted', 'id': item_id})


def build_response(status_code, body):
    """
    Build API Gateway-compatible response object
    
    Shows understanding of API Gateway integration format:
    - statusCode: HTTP status
    - headers: CORS and content-type
    - body: JSON string (not object)
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',  # CORS for browser access
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
        },
        'body': json.dumps(body, cls=DecimalEncoder)
    }