FROM alpine/k8s:1.28.2
RUN apk --no-cache add hey bc

COPY ../scripts/benchmark.sh /benchmark.sh
RUN chmod +x /benchmark.sh

ENTRYPOINT ["/benchmark.sh"]