import logging

import boto3

# Set up logging configuration
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def trigger_glue_crawler(crawler_name):
    """
    Trigger an AWS Glue Crawler by its name.

    Parameters:
        crawler_name (str): The name of the Glue Crawler to trigger.

    Logs the status of the crawler invocation and any exceptions encountered.
    """
    # Initialize the Glue client in the specified region
    client = boto3.client("glue", region_name="eu-west-2")

    try:
        # Start the Glue crawler
        response = client.start_crawler(Name=crawler_name)
        logger.info(f"Triggered Glue Crawler: {crawler_name}")

    except client.exceptions.CrawlerRunningException:
        # Handle the case where the crawler is already running
        logger.warning(f"Crawler {crawler_name} is already running.")

    except Exception as e:
        # Log any other errors that occur
        logger.error(f"Error triggering Glue Crawler: {str(e)}")
