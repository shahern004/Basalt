#! /bin/bash

# TODO preferred approach once we remove usage of download_and_extract.py
# cd /usr/local/share/ca-certificates/ && \
# curl -L -o- http://linuxrepo.rootforest.com/L3H/certs/l3harris_latest.tar.gz | tar -xvz && \
# update-ca-certificates && \
# cd -

python3 download_and_extract.py \
    http://linuxrepo.rootforest.com/L3H/certs/l3harris_latest.tar.gz \
    -d /usr/local/share/ca-certificates/ && \
update-ca-certificates

REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
CA_CERT_PATH==/etc/ssl/certs/ca-certificates.crt

exec "$@"
