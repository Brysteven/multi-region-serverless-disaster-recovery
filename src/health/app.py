import json
import os
import time
import boto3

table = boto3.resource("dynamodb").Table("dr-items")

def lambda_handler(event, context):
    try:
        region = os.environ.get("AWS_REGION", "")
        sk = "env:" + region
        ts = str(int(time.time()))
        table.put_item(Item={"pk": "health", "sk": sk, "ts": ts})
        item = table.get_item(Key={"pk": "health", "sk": sk}).get("Item", {})
        return {
            "statusCode": 200,
            "body": json.dumps({"status": "ok", "region": region, "ts": item.get("ts")}),
        }
    except Exception as e:
        return {"statusCode": 503, "body": json.dumps({"error": str(e)})}
