#!/usr/local/bin/python3

import os
import sys
import subprocess
import logging
import argparse
from datetime import datetime
import boto3

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Set environment variables
AWS_CREDENTIALS_PATH = os.getenv('AWS_CREDENTIALS_PATH', os.path.expanduser('~/.aws/credentials'))
ROUTE53_ZONE_ID = os.getenv('ROUTE53_ZONE_ID', 'Z09212343QAZF5V3E7654')
SNS_TOPIC_ARN = os.getenv('SNS_TOPIC_ARN', 'arn:aws:sns:us-east-1:123456789012:InfraAlerting')
S3_BACKUP_BUCKET = os.getenv('S3_BACKUP_BUCKET', 'company-infra-backup')
RECORDS_TO_VALIDATE = os.getenv('RECORDS_TO_VALIDATE',
                                'www.company-develop.com,api.company-develop.com,db.company-develop.com').split(',')


# Argument parsing
def parse_args():
    parser = argparse.ArgumentParser(description='Sync DNS zone from Route53 to local BIND server')
    parser.add_argument('--debug', action='store_true', help='Enable debug mode')
    parser.add_argument('--timestamp', default=datetime.now().strftime('%Y%m%d%H'), help='Timestamp for backup naming')
    return parser.parse_args()


# Verify AWS credentials
def verify_aws_credentials():
    if not os.path.isfile(AWS_CREDENTIALS_PATH):
        logging.error(f"AWS credentials file not found at {AWS_CREDENTIALS_PATH}")
        sys.exit(1)

    with open(AWS_CREDENTIALS_PATH, 'r') as f:
        if '[default]' not in f.read():
            logging.error("No [default] profile found in AWS credentials")
            sys.exit(1)

    logging.info("AWS credentials file verified.")


# Export AWS Route53 zone
def export_route53_zone(route53_zone_id, output_file):
    try:
        subprocess.check_call(['/opt/scripts/route53sync/cli53', 'export', route53_zone_id, '>', output_file],
                              shell=True)
        logging.info(f"Route53 zone {route53_zone_id} exported successfully.")
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to export Route53 zone: {e}")
        sys.exit(1)


# Validate exported zone file
def validate_zone_file(file_path):
    try:
        subprocess.check_call(['/opt/scripts/route53sync/cli53', 'validate', '--file', file_path], shell=True)
        logging.info(f"Zone file {file_path} validated successfully.")
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to validate zone file: {e}")
        sys.exit(1)


# Construct new zone file
def construct_zone_file(template_file, exported_file, constructed_file, timestamp):
    try:
        with open(template_file, 'r') as template, open(exported_file, 'r') as exported, open(constructed_file,
                                                                                              'w') as constructed:
            constructed.write(template.read())
            constructed.write(exported.read())
            constructed.write(f"\n; Zone file constructed at {timestamp}")
        logging.info(f"Zone file {constructed_file} constructed successfully.")
    except Exception as e:
        logging.error(f"Failed to construct zone file: {e}")
        sys.exit(1)


# Backup current BIND zone file
def backup_bind_zone(zone_file, backup_dir, timestamp):
    try:
        backup_path = os.path.join(backup_dir, f"{zone_file}.{timestamp}")
        subprocess.check_call(['cp', zone_file, backup_path])
        s3_client = boto3.client('s3')
        s3_client.upload_file(backup_path, S3_BACKUP_BUCKET, os.path.basename(backup_path))
        logging.info(f"BIND zone file {zone_file} backed up and uploaded to S3.")
    except Exception as e:
        logging.error(f"Failed to backup BIND zone file: {e}")
        sys.exit(1)


# Replace BIND zone file and reload
def replace_and_reload_bind_zone(constructed_file, zone_file):
    try:
        subprocess.check_call(['cp', constructed_file, zone_file])
        subprocess.check_call(['named-checkconf', '/etc/bind/named.conf'])
        subprocess.check_call(['/usr/sbin/rndc', 'reload'])
        os.remove(constructed_file)
        logging.info(f"BIND zone file replaced and DNS server reloaded.")
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to replace BIND zone file or reload DNS: {e}")
        sys.exit(1)


# Validate DNS records
def validate_dns_records(records, sns_topic_arn):
    sns_client = boto3.client('sns')
    for record in records:
        logging.info(f"Validating {record}...")
        dig_output = subprocess.getoutput(f"dig +short {record} @localhost")
        if not dig_output:
            error_message = f"DNS Validation Failed for {record}"
            logging.error(error_message)
            sns_client.publish(TopicArn=sns_topic_arn, Message=error_message)
            sys.exit(1)
        logging.info(f"{record} resolved to {dig_output}")


def main():
    args = parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    verify_aws_credentials()

    export_route53_zone(ROUTE53_ZONE_ID, '/opt/scripts/route53sync/company-int-exported.zone')
    validate_zone_file('/opt/scripts/route53sync/company-int-exported.zone')

    construct_zone_file('/opt/scripts/route53sync/company-develop.com-int.template',
                        '/opt/scripts/route53sync/company-int-exported.zone',
                        '/opt/scripts/route53sync/company-int-constructed.zone',
                        args.timestamp)

    backup_bind_zone('/etc/bind/master/company-develop.com', '/opt/backup-bind', args.timestamp)
    replace_and_reload_bind_zone('/opt/scripts/route53sync/company-int-constructed.zone',
                                 '/etc/bind/master/company-develop.com')

    validate_dns_records(RECORDS_TO_VALIDATE, SNS_TOPIC_ARN)

    logging.info("All operations completed successfully.")


if __name__ == '__main__':
    main()
