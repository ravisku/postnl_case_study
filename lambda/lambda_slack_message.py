import json
import os

import urllib3

http = urllib3.PoolManager()
webhook_url = (
    "https://hooks.slack.com/services/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"
)


def lambda_handler(event, context):
    # Extract the Glue job name and error message from the event
    print(event)
    detail = event.get("detail", {})
    print(detail)
    job_name = detail.get("jobName", "Unknown Job")
    state = detail.get("state", "Unknown State")

    # Only trigger on job failure
    if state != "FAILED":
        return

    # Prepare the Slack message
    message = {
        "text": f"🚨 AWS Glue Job Failed: {job_name}\n\nDetails: {json.dumps(detail, indent=2)}"
    }

    # Send the message to Slack
    response = http.request(
        "POST",
        webhook_url,
        body=json.dumps(message),
        headers={"Content-Type": "application/json"},
    )
    print(response)
    return {"statusCode": response.status, "response": response.data.decode("utf-8")}
