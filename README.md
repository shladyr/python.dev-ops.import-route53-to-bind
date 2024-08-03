# DNS Zone Sync Script

This Python script is designed to synchronize DNS zones from AWS Route53 to a local BIND server. It handles exporting zones from Route53, validating and constructing zone files, backing up existing zone files, replacing and reloading BIND zones, and validating DNS records.

## Features

- **AWS Credentials Verification:** Ensures that the AWS credentials file exists and contains the `[default]` profile.
- **Route53 Zone Export:** Exports a specified Route53 zone to a local file using the `cli53` command-line tool.
- **Zone File Validation:** Validates the exported zone file for correctness.
- **Zone File Construction:** Constructs a new zone file by combining a template with the exported zone.
- **BIND Zone Backup:** Backs up the current BIND zone file locally and uploads it to an S3 bucket.
- **BIND Zone Replacement and Reload:** Replaces the existing BIND zone file with the newly constructed one and reloads the DNS server.
- **DNS Record Validation:** Validates the DNS records by resolving them locally and sends an alert to an SNS topic if any validation fails.
- **Logging:** Provides detailed logging throughout the process for easy troubleshooting and monitoring.

## Requirements

- Python 3.x
- `boto3` package for AWS interactions
- `cli53` command-line tool for Route53 interactions
- BIND DNS server installed locally
- AWS credentials configured

## Installation

1. **Install Python Dependencies:**

    ```sh
    pip install boto3
    ```

2. **Install `cli53` Tool:**

    Follow the instructions to install `cli53` on your system. It's required for exporting and validating Route53 zones.

3. **Set Up Environment Variables:**

    Ensure the following environment variables are set:

    ```sh
    export AWS_CREDENTIALS_PATH=~/.aws/credentials
    export ROUTE53_ZONE_ID=your_route53_zone_id
    export SNS_TOPIC_ARN=arn:aws:sns:your-region:your-account-id:your-topic-name
    export S3_BACKUP_BUCKET=your-s3-bucket-name
    export RECORDS_TO_VALIDATE='record1.com,record2.com,record3.com'
    ```

## Usage

To run the script, use the following command:

```sh
python dns_sync.py [--debug] [--timestamp TIMESTAMP]
```
```sh
--debug: Enable debug mode for more verbose logging.
--timestamp: Specify a timestamp for backup naming (default is the current date and hour)
```

## How It Works

1. **Verify AWS Credentials:** 
    - The script checks if the AWS credentials file exists at the specified path and ensures that it contains a `[default]` profile. If the file or profile is missing, the script will terminate with an error.

2. **Export Route53 Zone:** 
    - The script uses the `cli53` command-line tool to export the specified Route53 zone to a local file. If the export fails, the script logs the error and exits.

3. **Validate Zone File:** 
    - After exporting the zone, the script validates the zone file using the `cli53` tool. This ensures that the exported DNS records are correct and that the file is in a valid format.

4. **Construct Zone File:** 
    - The script constructs a new zone file by combining a pre-existing template file with the exported zone file. The resulting file is stamped with a timestamp for version tracking.

5. **Backup BIND Zone:** 
    - The current BIND zone file is backed up locally with a timestamped filename. The backup is then uploaded to an S3 bucket for secure storage. If the backup or upload fails, the script logs the error and exits.

6. **Replace and Reload BIND Zone:** 
    - The newly constructed zone file replaces the current zone file on the BIND server. The script then reloads the DNS server configuration using `rndc` commands to apply the changes. Any failure during this process is logged, and the script will terminate.

7. **Validate DNS Records:** 
    - The script performs DNS lookups for a list of specified records to ensure they resolve correctly. If any record fails to resolve, an error is logged, and an alert is sent to the specified SNS topic. The script will exit after sending the alert.

## Error Handling

- The script includes comprehensive error handling at each stage. If a critical error occurs (e.g., missing credentials, failed file validation, or failed DNS resolution), the script will log the error with detailed information and terminate execution to prevent any adverse effects on the DNS configuration.

- All logs are time-stamped and include the log level (INFO, ERROR, DEBUG), providing a clear audit trail of the script's operations.

## License

This script is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request with your changes.

## Contact

For any inquiries or support, please contact the script maintainer at `serhii.hladyr.ukr@gmail.com`.
