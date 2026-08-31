#!/bin/bash
set -e
SKIP_AWS=false
while getopts ":s" opt; do
  case $opt in
  s)
    SKIP_AWS=true
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    exit 1
    ;;
  esac
done
# Remove parsed options from $@, leaving only positional args
shift $((OPTIND - 1))
IP=$1
BUCKET=$2 #path under script can find ca.key and ca.crt
NAME=$3
ENV=$4

if [[ $SKIP_AWS == true ]]; then
  NAME="name"
  ENV="env"
fi

if [[ $IP == "" || $NAME == "" || $ENV == "" || $BUCKET == "" ]]; then
  echo "./sign-cert.sh [-s] <IP> <BUCKET> <NAME> <ENV>"
  echo "-s to skip aws upload"
  exit 1
fi

#get ca
aws s3 cp s3://$BUCKET/ca.key ca.key
aws s3 cp s3://$BUCKET/ca.crt ca.crt
#issue request and sign
openssl genrsa -out tls.key
openssl req -new -key tls.key -out tls.csr -subj "/CN=$IP" -addext "subjectAltName=IP:$IP"
openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -out tls.crt -days 365 -copy_extensions copy

if [[ $SKIP_AWS == false ]]; then
  #upload to ssm
  KEY=$(cat tls.key)
  CERT=$(cat tls.crt)
  PARAM=$(jq -n --arg key "$KEY" --arg cert "$CERT" '{key: $key, cert: $cert}')
  aws ssm put-parameter --name "/clusters/$ENV/ca/$NAME" --value "$PARAM" --type "SecureString" --overwrite
  rm tls.key
  rm tls.crt
fi
#remove leftovers
rm ca.crt
rm ca.key
rm tls.csr
