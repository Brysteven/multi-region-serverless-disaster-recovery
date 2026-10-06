import json
import boto3

table = boto3.resource("dynamodb").Table("dr-items")


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except Exception:
        return {"statusCode": 400, "body": json.dumps({"error": "invalid json"})}

    item_id = body.get("id")
    data = body.get("data")
    if not item_id or not data:
        return {"statusCode": 400, "body": json.dumps({"error": "id and data required"})}

    table.put_item(Item={"pk": "item:" + item_id, "sk": "meta", "data": data, "id": item_id})
    return {"statusCode": 201, "body": json.dumps({"id": item_id})}
