FROM amazon/aws-cli:2.36.49
RUN dnf install -y postgresql17 jq openssl curl-minimal && dnf clean all
ENTRYPOINT ["/bin/sh", "-c"]
