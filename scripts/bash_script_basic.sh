#!/bin/bash

# The script used to get copy of AWS company-develop.com
# DNS internal zone from Route53 and
# import it into local DNS zone.

##################  VARIABLES  ##################
route53zoneid=Z09212343QAZF5V3E7654
TIMESTAMP=$(date +%Y%m%d%H)
snsTopic="arn:aws:sns:us-east-1:123456789012:InfraAlerting"
LOCKFILE="/tmp/dns_sync.lock"

##################  CHECK CLI TOOL  ##################
if ! command -v /opt/scripts/cli53 &> /dev/null; then
    echo "cli53 not found, exiting."
    exit 1
fi

##################  CREATE LOCK FILE  ##################
if [ -e $LOCKFILE ]; then
    echo "Script is already running. Exiting."
    exit 1
fi
touch $LOCKFILE

##################  VERIFYING AWS CREDENTIALS  ##################
if [ ! -f ~/.aws/credentials ]; then
    echo "ERROR: AWS credentials file not found at ~/.aws/credentials"
    rm -f $LOCKFILE
    exit 1
fi

if ! grep -q '\[default\]' ~/.aws/credentials; then
    echo "ERROR: No [default] profile found in ~/.aws/credentials"
    rm -f $LOCKFILE
    exit 1
fi

echo "AWS credentials file verified."

##################  EXPORTING AWS ZONE  ##################
/opt/scripts/route53sync/cli53 export $route53zoneid > /opt/scripts/route53sync/company-int-exported.zone
/opt/scripts/route53sync/cli53 validate --file company-int-exported.zone
sed -i 1,19d /opt/scripts/route53sync/company-int-exported.zone

##################  CONSTRUCTING ZONE  ##################
cat /opt/scripts/route53sync/company-develop.com-int.template > /opt/scripts/route53sync/company-int-constructed.zone
cat /opt/scripts/route53sync/company-int-exported.zone >> /opt/scripts/route53sync/company-int-constructed.zone
sed -i "s/0000000000/$TIMESTAMP/g" /opt/scripts/route53sync/company-int-constructed.zone

##################  BACKUPING BIND ZONE ##################
cat /etc/bind/master/company-develop.com > /opt/backup-bind/company-develop.com.$TIMESTAMP
aws s3 sync /opt/backup-bind s3://company-infra-backup/backup-bind/

##################  REPLACING ZONE  ##################
cat /opt/scripts/route53sync/company-int-constructed.zone > /etc/bind/master/company-develop.com
named-checkconf /etc/bind/named.conf
/usr/sbin/rndc reload
rm -fv /opt/scripts/route53sync/company-int-constructed.zone /opt/scripts/route53sync/company-int-exported.zone

##################  VALIDATING & ALERTING ##################
# Define the list of records to validate
RECORDS=("www.company-develop.com" "api.company-develop.com" "db.company-develop.com")

for record in "${RECORDS[@]}"
do
    echo "Validating $record..."
    dig_output=$(dig +short $record @localhost)
    if [ -z "$dig_output" ]; then
        echo "ERROR: $record did not resolve correctly."
        aws sns publish --topic-arn $snsTopic --message "DNS Validation Failed for $record"
        rm -f $LOCKFILE
        exit 1
    else
        echo "$record resolved to $dig_output"
    fi
done

echo "All records validated successfully."

##################  CLEAN UP LOCK FILE  ##################
rm -f $LOCKFILE

exit 0
