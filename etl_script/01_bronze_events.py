import logging

import boto3
from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    current_timestamp,
    dayofmonth,
    input_file_name,
    month,
    regexp_extract,
    to_date,
    year,
)

from common_utils import trigger_glue_crawler

# Initialize Spark Session
spark = SparkSession.builder.appName("ETL Pipeline for bronze layer").getOrCreate()

# Define file paths for source data and the Bronze layer destination.
bronze_path = "ss3://postnl-case-study/target_files/bronze/events/"
source_path = "s3://postnl-case-study/source_file/"
crawler_name = "bronze_events_crawler"

# Set up logging configuration
# INFO level logs will capture general information and process flow.
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def load_bronze_layer(source_path, bronze_path):
    """
    Load data into the Bronze layer by reading source files, adding metadata,
    and saving it in a partitioned format for efficient querying.

    Parameters:
    - source_path (str): S3 path for the source files.
    - bronze_path (str): S3 path for the Bronze layer destination.
    """
    try:
        logger.info("Starting Bronze Layer ETL process.")

        # Read source CSV file(s)
        logger.info(f"Reading data from source path: {source_path}")
        df = spark.read.csv(
            source_path, header=True, inferSchema=True, quote='"', escape='"'
        )

        # Add metadata and partition columns
        logger.info("Adding metadata columns: file_path and execution_datetime.")
        df = df.withColumn(
            "file_path", regexp_extract(input_file_name(), "(.*/)", 1)
        ).withColumn("execution_datetime", current_timestamp())

        # Write data to Bronze layer
        # Using partitioning for optimized access and enabling schema evolution for data flexibility.
        logger.info(
            f"Writing data to Bronze path with schema evolution enabled: {bronze_path}"
        )
        df.repartition(1).write.mode("overwrite").option("mergeSchema", "true").parquet(
            bronze_path
        )

        logger.info("Bronze Layer ETL process completed successfully.")
    except Exception as e:
        logger.error(f"Error in Bronze Layer ETL process: {e}")
        raise


if __name__ == "__main__":
    # Execute Bronze layer ETL
    logger.info("Starting bronze layer ETL Pipeline.")
    load_bronze_layer(source_path, bronze_path)
    logger.info("ETL Pipeline for bronze layer executed successfully.")

    # Trigger the Glue crawler to update the data catalog with new data.
    logger.info("Triggering Glue crawler for Bronze layer table.")
    trigger_glue_crawler(crawler_name)
    logger.info("Glue crawler for Bronze layer table executed successfully.")
