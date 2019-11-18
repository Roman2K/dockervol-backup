# --- Build image
FROM ruby:2.5.5-alpine3.10 as builder
ARG rclone_version=1.49.3

# bundle install deps
RUN apk add --update ca-certificates git build-base openssl-dev
RUN gem install bundler -v '>= 2'

# rclone
RUN cd /tmp \
  && wget https://github.com/rclone/rclone/releases/download/v${rclone_version}/rclone-v${rclone_version}-linux-amd64.zip \
  && unzip rclone-*.zip \
  && mv rclone-*/rclone /

# bundle install
COPY . /app
RUN cd /app && bundle

# --- Runtime image
FROM ruby:2.5.5-alpine3.10

COPY --from=builder /rclone /opt/rclone
COPY --from=builder /app /app
COPY --from=builder /app/docker/rclone /usr/bin/rclone
COPY --from=builder /usr/local/bundle /usr/local/bundle

RUN addgroup -g 122 -S docker
RUN apk --update upgrade && apk add --no-cache docker

RUN addgroup -g 1000 -S app \
  && adduser -u 1000 -S app -G app \
  && addgroup app docker \
  && chown -R app: /app

USER app
RUN cd \
  && mkdir -p .config/rclone \
  && chmod 700 .config

WORKDIR /app
ENTRYPOINT ["./docker/entrypoint"]
