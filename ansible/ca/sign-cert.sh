#!/bin/bash

set -e

IP=$1
NAME=$2
ENV=$3
BUCKET=$4 #path under script can find ca.key and ca.crt

if [[ $IP == "" || $NAME == "" || $ENV == "" || $BUCKET == "" ]]; then
	echo "./sign-cert.sh <IP> <NAME> <ENV> <BUCKET>"
	exit 1
fi

#get ca
aws s3 cp s3://$BUCKET/ca.key ca.key
aws s3 cp s3://$BUCKET/ca.crt ca.crt

#issue request and sign
openssl genrsa -out tls.key
openssl req -new -key tls.key -out tls.csr -subj "/CN=$IP" -addext "subjectAltName=IP:$IP"
openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -out tls.crt -days 365 -copy_extensions copy

#upload to ssm
KEY=$(cat tls.key)
CERT=$(cat tls.crt)

PARAM=$(jq -n --arg key "$KEY" --arg cert "$CERT" '{key: $key, cert: $cert}')

aws ssm put-parameter --name "/clusters/$ENV/ca/$NAME" --value "$PARAM" --type "SecureString" --overwrite

#remove leftovers
rm ca.crt
rm ca.key
rm tls.csr
rm tls.key
rm tls.crt
