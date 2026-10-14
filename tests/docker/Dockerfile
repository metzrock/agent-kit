FROM ubuntu:24.04
RUN apt-get update -qq && apt-get install -y -qq bash git jq curl ca-certificates && rm -rf /var/lib/apt/lists/*
COPY . /kit
WORKDIR /kit
RUN chmod +x bin/agent-kit tests/docker/smoke.sh
CMD ["bash", "tests/docker/smoke.sh"]
