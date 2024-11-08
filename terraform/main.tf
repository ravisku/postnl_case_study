provider "aws" {
  region = "eu-west-2"
}

terraform {
  backend "s3" {
    bucket  = "post-nl-assignment"
    key     = "terraform_state/terraform.tfstate"
    region  = "eu-west-2"
    encrypt = true
  }
}

resource "aws_iam_role" "glue_role" {
  name = "glue-role-pnl"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Action" : "sts:AssumeRole",
      "Principal" : {
        "Service" : "glue.amazonaws.com"
      },
      "Effect" : "Allow",
      "Sid" : ""
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_role_attach" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_s3_bucket" "postnl-case-study" {
  bucket = "postnl-case-study"
}

resource "aws_iam_policy" "glue_s3_access_policy" {
  name        = "glue-s3-access-policy-pnl"
  description = "Policy for S3 access to a specific bucket for Glue jobs"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        "Resource" : [
          "arn:aws:s3:::postnl-case-study",
          "arn:aws:s3:::postnl-case-study/*"
        ]
      }
    ]
  })
}

# Attach the S3 access policy to the Glue role
resource "aws_iam_role_policy_attachment" "glue_s3_policy_attach" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_s3_access_policy.arn
}

# Define Glue ETL Job for Bronze Layer
resource "aws_glue_job" "bronze_job" {
  name     = "bronze-events-job"
  role_arn = aws_iam_role.glue_role.arn

  command {
    # GitHub Actions will provide the location of the script in S3
    script_location = var.bronze_script_location
    python_version  = "3"
  }

  default_arguments = {
    "--extra-py-files" = var.common_utils_location
  }
}


resource "aws_glue_catalog_database" "bronze_database" {
  name = "bronze"
}

resource "aws_glue_crawler" "bronze_crawler" {
  name = "bronze_events_crawler"
  role = aws_iam_role.glue_role.arn

  database_name = aws_glue_catalog_database.bronze_database.name

  s3_target {
    path = "s3://postnl-case-study/target_files/bronze/events/"
  }

  configuration = jsonencode({
    "Version" : 1.0,
    "Grouping" : {
      "TableGroupingPolicy" : "CombineCompatibleSchemas"
    }
  })
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_eventbridge_to_slack_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Principal = { Service = "lambda.amazonaws.com" },
        Effect    = "Allow",
        Sid       = ""
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_logs" {
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "notify_slack_on_failure" {
  function_name = "notify_slack_on_glue_failure"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"
  timeout       = 10

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }

  # Inline Python code for the Lambda function
  source_code_hash = filebase64sha256(var.lambda_script_location)
  filename         = var.lambda_script_location
}

resource "aws_cloudwatch_event_rule" "glue_job_failure_rule" {
  name        = "glue_job_failure_rule"
  description = "Triggers Lambda when a Glue job fails"
  event_pattern = jsonencode({
    "source" : ["aws.glue"],
    "detail-type" : ["Glue Job State Change"],
    "detail" : {
      "jobName" : "bronze-events-job",
      "state" : ["FAILED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "send_to_lambda" {
  rule      = aws_cloudwatch_event_rule.glue_job_failure_rule.name
  target_id = "send_to_lambda"
  arn       = aws_lambda_function.notify_slack_on_failure.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notify_slack_on_failure.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.glue_job_failure_rule.arn
}

# Variables for script and dependency locations
variable "bronze_script_location" {}
variable "common_utils_location" {}
variable "lambda_script_location" {}
