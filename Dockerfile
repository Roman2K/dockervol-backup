# --- Build image
FROM ruby:2.7.2-alpine3.13
ARG rclone_version=1.55.1

# bundle install deps
RUN apk add --update ca-certificates git build-base openssl-dev
RUN gem install bundler -v '>= 2'

# rclone
RUN cd /tmp \
  && wget https://github.com/rclone/rclone/releases/download/v${rclone_version}/rclone-v${rclone_version}-linux-amd64.zip \
  && unzip rclone-*.zip \
  && mv rclone-*/rclone /

# bundle install
WORKDIR /app
COPY Gemfile* ./
RUN bundle

# --- Runtime image
FROM ruby:2.7.2-alpine3.13

COPY --from=0 /rclone /opt/rclone
COPY --from=0 /usr/local/bundle /usr/local/bundle

RUN apk --update upgrade && apk add --no-cache docker openssh-client

RUN echo $' \
Host *\n \
  StrictHostKeyChecking no\n \
  UserKnownHostsFile=/dev/null\n \
' > /etc/ssh/ssh_config

# /app
RUN addgroup -g 998 -S docker2
RUN addgroup -g 1000 -S app \
  && adduser -u 1000 -S app -G app \
  && addgroup app docker2
WORKDIR /app
COPY . .
COPY ./docker/rclone /usr/bin/rclone
RUN chown -R app: .
USER app
RUN (cd \
  && mkdir -p .config/rclone \
  && chmod 700 .config)

ENTRYPOINT ["./docker/entrypoint"]
