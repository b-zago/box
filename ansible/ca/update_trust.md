#Update trust certs

##Fedora / RHEL

sudo cp ca.crt /etc/pki/ca-trust/source/anchors/ && update-ca-trust extract

##Debian / Ubuntu

sudo cp ca.crt /usr/local/share/ca-certificates/ && update-ca-certificates
