#!/bin/bash

##################  ENVIRONMENT VARIABLES  ##################
: "${ROUTE53_ZONE_ID:?Environment variable ROUTE53_ZONE_ID must be set}"
: "${SNS_TOPIC_ARN:?Environment variable SNS_TOPIC_ARN must be set}"
: "${S3_BACKUP_BUCKET:?Environment variable S3_BACKUP_BUCKET must be set}"
: "${BIND_ZONE_DIR:?Environment variable BIND_ZONE_DIR must be set}"
: "${BACKUP_DIR:?Environment variable BACKUP_DIR must be set}"
: "${TEMPLATE_FILE:?Environment variable TEMPLATE_FILE must be set}"
: "${DEBUG:=0}" # Set DEBUG=1 for debugging

##################  PARAMETERS  ##################
TIMESTAMP=$(date +%Y%m%d%H)
LOG_FILE="/var/log/dns_sync.log"

##################  FUNCTIONS  ##################

log_message() {
    local log_level="$1"
    shift
    local message="$@"
    echo "$(date +"%Y-%m-%d %H:%M:%S") [$log_level] $message" | tee -a "$LOG_FILE"
}

error_exit() {
    log_message "ERROR" "$1"
    exit 1
}

debug() {
    if [ "$DEBUG" -eq 1 ]; then
        log_message "DEBUG" "$@"
    fi
}

verify_aws_credentials() {
    if [ ! -f ~/.aws/credentials ]; then
        error_exit "AWS credentials file not found at ~/.aws/credentials"
    fi

    if ! grep -q '\[default\]' ~/.aws/credentials; then
        error_exit "No [default] profile found in ~/.aws/credentials"
    fi

    log_message "INFO" "AWS credentials file verified."
}

export_aws_zone() {
    /opt/scripts/route53sync/cli53 export "$ROUTE53_ZONE_ID" > /opt/scripts/route53sync/company-int-exported.zone \
        || error_exit "Failed to export AWS Route53 zone"
    /opt/scripts/route53sync/cli53 validate --file /opt/scripts/route53sync/company-int-exported.zone \
        || error_exit "Failed to validate exported zone file"
    sed -i 1,19d /opt/scripts/route53sync/company-int-exported.zone
    debug "AWS zone exported and validated."
}

construct_zone() {
    cat "$TEMPLATE_FILE" > /opt/scripts/route53sync/company-int-constructed.zone
    cat /opt/scripts/route53sync/company-int-exported.zone >> /opt/scripts/route53sync/company-int-constructed.zone
    sed -i "s/0000000000/$TIMESTAMP/g" /opt/scripts/route53sync/company-int-constructed.zone
    debug "Zone file constructed."
}

backup_bind_zone() {
    cp "$BIND_ZONE_DIR/company-develop.com" "$BACKUP_DIR/company-develop.com.$TIMESTAMP" \
        || error_exit "Failed to backup BIND zone file"
    aws s3 sync "$BACKUP_DIR" "s3://$S3_BACKUP_BUCKET/" \
        || error_exit "Failed to sync backup to S3"
    log_message "INFO" "BIND zone backup completed and synced to S3."
}

replace_zone() {
    cp /opt/scripts/route53sync/company-int-constructed.zone "$BIND_ZONE_DIR/company-develop.com" \
        || error_exit "Failed to replace BIND zone file"
    named-checkconf /etc/bind/named.conf || error_exit "BIND configuration check failed"
    /usr/sbin/rndc reload || error_exit "Failed to reload BIND server"
    rm -fv /opt/scripts/route53sync/company-int-constructed.zone /opt/scripts/route53sync/company-int-exported.zone
    log_message "INFO" "Zone file replaced and BIND server reloaded."
}

validate_records() {
    local RECORDS=("www.company-develop.com" "api.company-develop.com" "db.company-develop.com")
    for record in "${RECORDS[@]}"
    do
        log_message "INFO" "Validating $record..."
        dig_output=$(dig +short "$record" @localhost)
        if [ -z "$dig_output" ]; then
            error_exit "DNS Validation Failed for $record"
            aws sns publish --topic-arn "$SNS_TOPIC_ARN" --message "DNS Validation Failed for $record"
        else
            log_message "INFO" "$record resolved to $dig_output"
        fi
    done
    log_message "INFO" "All records validated successfully."
}

show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -d, --debug         Enable debug mode"
}

##################  MAIN SCRIPT  ##################
while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
  -h | --help )
    show_help
    exit 0
    ;;
  -d | --debug )
    DEBUG=1
    ;;
esac; shift; done
if [[ "$1" == '--' ]]; then shift; fi

verify_aws_credentials
export_aws_zone
construct_zone
backup_bind_zone
replace_zone
validate_records

exit 0
