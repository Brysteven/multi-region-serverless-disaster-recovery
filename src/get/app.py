import json
import boto3

table = boto3.resource("dynamodb").Table("dr-items")


def lambda_handler(event, context):
    item_id = event.get("pathParameters", {}).get("id")
    item = table.get_item(Key={"pk": "item:" + item_id, "sk": "meta"}).get("Item")
    if item is None:
        return {"statusCode": 404, "body": json.dumps({"error": "not found"})}
    return {"statusCode": 200, "body": json.dumps(item)}
