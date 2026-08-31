#!/bin/bash

set -e

BUCKET=$1 #path where to upload ca.key and ca.crt
CN=$2

if [[ $BUCKET == "" || $CN == "" ]]; then
	echo "./ca_make.sh <BUCKET> <CN>"
	exit 1
fi

#gen ca
openssl genrsa -out ca.key 4096
openssl req -new -x509 -key ca.key -out ca.crt -subj "/CN=$CN" -days 3650

#upload ca
aws s3 cp ca.key s3://$BUCKET/ca.key
aws s3 cp ca.crt s3://$BUCKET/ca.crt  

#leave out public one for self-trust configuration for user
rm ca.key
