FROM amazon/aws-cli:2.36.49
RUN dnf install -y postgresql16 jq && dnf clean all
COPY bootstrap.sql /sql/bootstrap.sql
ENTRYPOINT ["/bin/sh", "-c"]
