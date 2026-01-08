FROM ubuntu:24.04@sha256:c35e29c9450151419d9448b0fd75374fec4fff364a27f176fb458d472dfc9e54
RUN apt update && apt install -y jq rsync zip
WORKDIR /burrow
COPY --chown=1001:1001 README.md .
COPY --chown=1001:1001 entrypoint.sh .
ENTRYPOINT [ "./entrypoint.sh" ]
