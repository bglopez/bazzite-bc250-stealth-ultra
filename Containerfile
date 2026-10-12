FROM ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest

ARG XONE_COMMIT
ENV XONE_COMMIT=${XONE_COMMIT}
COPY build-xone.sh /tmp/build-xone.sh
RUN chmod +x /tmp/build-xone.sh && /tmp/build-xone.sh && rm /tmp/build-xone.sh
RUN bootc container lint
