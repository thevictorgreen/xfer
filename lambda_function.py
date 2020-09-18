import base64
import boto3
from boto3.dynamodb.conditions import Key, Attr
import datetime
import decimal
import json
import logging
import os
import time
import warnings
import requests
import string
import random


def gen_randomID():
    N = 10
    result = ''.join(random.choices(string.ascii_lowercase + string.digits, k = N))
    return str(result)


def register(event):
    body = json.loads(event['body'])
    user_id = body['user_id'] #gen_randomID()
    user_name = body['user_name']
    user_bucket = body['user_bucket'] #"onecloud-" + user_id
    dynamodb = boto3.resource('dynamodb')
    APIGatewayUsersTable = dynamodb.Table('APIGatewayUsersTable')
    APIGatewayUsersTable.put_item(
       Item={
         'UserName': user_name,
         'UserID': user_id,
         'UserBucket': user_bucket,
         'cloud_architectures': [],
       }
    )
    return 'success','user account registered',200


def deploy(event):
    body        = json.loads(event['body'])
    provider    = body['provider']
    region      = body['region']
    environment = body['environment']
    user_name   = body['user_name']
    user_id     = body['user_id']
    user_bucket = body['user_bucket']

    cloud_architecture_id = gen_randomID()
    cloud_status = 'config_created'

    task_id = gen_randomID()
    task_status = 'unassigned'

    architecture = {}
    architecture['cloud_architecture_id'] = cloud_architecture_id
    architecture['provider'] = provider
    architecture['region'] = region
    architecture['environment'] = environment
    architecture['cloud_status'] = cloud_status

    task = {}
    task['task_id'] = task_id
    task['task_status'] = task_status
    task['task_node'] = 'unassigned'
    task['user'] = {}
    task['user']['user_id'] = user_id
    task['user']['user_name'] = user_name
    task['user']['user_bucket'] = user_bucket
    task['architecture'] = {}
    task['architecture'] = architecture

    dynamodb = boto3.resource('dynamodb')
    APIGatewayUsersTable = dynamodb.Table('APIGatewayUsersTable')
    APIGatewayTasksTable = dynamodb.Table('APIGatewayTasksTable')

    APIGatewayUsersTable.update_item(
        Key={
            'UserName': user_name,
            'UserID': user_id
        },
        UpdateExpression='SET cloud_architectures = list_append(cloud_architectures,:i)',
        ExpressionAttributeValues={
            ':i': [architecture],
        }
    )

    APIGatewayTasksTable.put_item(
       Item={
         'TaskStatus': task['task_status'],
         'TaskID': task['task_id'],
         'TaskNode': task['task_node'],
         'User': task['user'],
         'Architecture': task['architecture']
       }
    )
    return 'success','cloud architecture created',200


def consumetask(event):
    body      = json.loads(event['body'])
    task_node = body['task_node']
    tha_task = {}
    tha_task['status'] = 'empty'
    tha_task['object'] = {}

    dynamodb = boto3.resource('dynamodb')
    APIGatewayUsersTable = dynamodb.Table('APIGatewayUsersTable')
    APIGatewayTasksTable = dynamodb.Table('APIGatewayTasksTable')

    response = APIGatewayTasksTable.scan(
        FilterExpression=Attr('TaskStatus').eq('unassigned'),
    )

    if response['Count'] >= 1:
        task = response['Items'][0]
        task_id = task['TaskID']
        task_status = 'running'
        user_id = task['User']['user_id']
        user_name = task['User']['user_name']
        cloud_architecture_id = task['Architecture']['cloud_architecture_id']

        task['TaskStatus'] = task_status
        task['TaskNode'] = task_node

        #Update Task Object
        APIGatewayTasksTable.update_item(
            Key={
             'TaskID': task_id
            },
            UpdateExpression='SET TaskNode = :i',
            ExpressionAttributeValues={
             ':i': task_node
            }
        )

        APIGatewayTasksTable.update_item(
            Key={
             'TaskID': task_id
            },
            UpdateExpression='SET TaskStatus = :i',
            ExpressionAttributeValues={
             ':i': task_status
            }
        )

        #Update User Object
        response = APIGatewayUsersTable.get_item(
            Key={
                'UserName': user_name,
                'UserID': user_id
            }
        )

        item = response['Item']
        cloud_architectures = item['cloud_architectures']
        index = 0
        for i in range(len(cloud_architectures)):
            if cloud_architectures[i]['cloud_architecture_id'] == cloud_architecture_id:
                index = i
                break

        new_architecture = {}
        new_architecture['cloud_architecture_id'] = cloud_architectures[index]['cloud_architecture_id']
        new_architecture['provider'] = cloud_architectures[index]['provider']
        new_architecture['region'] = cloud_architectures[index]['region']
        new_architecture['environment'] = cloud_architectures[index]['environment']
        new_architecture['status'] = 'deploying'

        query = "REMOVE cloud_architectures[%d]" % (index)
        APIGatewayUsersTable.update_item(
            Key={
                'UserName': user_name,
                'UserID': user_id
            },
            UpdateExpression=query
        )

        APIGatewayUsersTable.update_item(
            Key={
                'UserName': user_name,
                'UserID': user_id
            },
            UpdateExpression='SET cloud_architectures = list_append(cloud_architectures,:i)',
            ExpressionAttributeValues={
                ':i': [new_architecture],
            }
        )

        tha_task['status'] = 'present'
        tha_task['object'] = task

    else:
        tha_task['status'] = 'empty'

    return 'success','task queue has been queried',200,tha_task


def marktaskcomplete(event):
    body                  = json.loads(event['body'])
    task_id               = body['task_id']
    task_status           = body['task_status']
    user_name             = body['user_name']
    user_id               = body['user_id']
    cloud_architecture_id = body['cloud_architecture_id']

    dynamodb = boto3.resource('dynamodb')
    APIGatewayUsersTable = dynamodb.Table('APIGatewayUsersTable')
    APIGatewayTasksTable = dynamodb.Table('APIGatewayTasksTable')

    #Update Task Object
    APIGatewayTasksTable.update_item(
        Key={
            'TaskID': task_id
        },
        UpdateExpression='SET TaskStatus = :i',
        ExpressionAttributeValues={
            ':i': task_status
        }
    )

    #Update User Object
    response = APIGatewayUsersTable.get_item(
        Key={
            'UserName': user_name,
            'UserID': user_id
        }
    )

    item = response['Item']
    cloud_architectures = item['cloud_architectures']
    index = 0
    for i in range(len(cloud_architectures)):
        if cloud_architectures[i]['cloud_architecture_id'] == cloud_architecture_id:
            index = i
            break

    new_architecture = {}
    new_architecture['cloud_architecture_id'] = cloud_architectures[index]['cloud_architecture_id']
    new_architecture['provider'] = cloud_architectures[index]['provider']
    new_architecture['region'] = cloud_architectures[index]['region']
    new_architecture['environment'] = cloud_architectures[index]['environment']
    new_architecture['status'] = 'deployed'

    query = "REMOVE cloud_architectures[%d]" % (index)
    APIGatewayUsersTable.update_item(
        Key={
            'UserName': user_name,
            'UserID': user_id
        },
        UpdateExpression=query
    )
    APIGatewayUsersTable.update_item(
        Key={
            'UserName': user_name,
            'UserID': user_id
        },
        UpdateExpression='SET cloud_architectures = list_append(cloud_architectures,:i)',
        ExpressionAttributeValues={
            ':i': [new_architecture],
        }
    )
    return 'success','task has been completed',200


def inventory(event):
    body      = json.loads(event['body'])
    return 'success','inventory',200


# Entry Point
def lambda_handler(event, context):

    #0. Dump incoming data
    print(event)
    print(json.loads(event['body']))

    #1. Construct apiResponse object
    apiResponse = {}
    apiResponse['status'] = ''
    apiResponse['message'] = ''

    #2. Construct http responseObject
    responseObject = {}
    responseObject['statusCode'] = 200
    responseObject['headers'] = {}
    responseObject['headers']['Content-Type'] = 'application/json'

    #3. Check Method
    if event['httpMethod'] == 'POST':

        # Check Path /register
        if event['path'] == '/register':
            # Implement logic
            apiResponse['status'], apiResponse['message'], responseObject['statusCode'] = register(event)

        # Check Path /deploy
        if event['path'] == '/deploy':
            # Implement logic
            apiResponse['status'], apiResponse['message'], responseObject['statusCode'] = deploy(event)

        # Check Path /consumetask
        if event['path'] == '/consumetask':
            # Implement logic
            apiResponse['status'], apiResponse['message'], responseObject['statusCode'], apiResponse['task'] = consumetask(event)

        # Check Path /marktaskcomplete
        if event['path'] == '/marktaskcomplete':
            # Implement logic
            apiResponse['status'], apiResponse['message'], responseObject['statusCode'] = marktaskcomplete(event)

        # Check Path /inventory
        if event['path'] == '/inventory':
            # Implement logic
            apiResponse['status'], apiResponse['message'], responseObject['statusCode'] = inventory(event)

    #4. return http response object
    responseObject['body'] = json.dumps(apiResponse)
    return responseObject
