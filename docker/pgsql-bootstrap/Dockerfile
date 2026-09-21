FROM amazon/aws-cli:2.36.49
RUN dnf install -y postgresql16 jq && dnf clean all
ENTRYPOINT ["/bin/sh", "-c"]
