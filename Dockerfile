FROM ubuntu:23.10

RUN apt-get update && \
    apt-get install -y -q build-essential ruby ruby-dev llvm-16-dev git && \
    gem install bundler

COPY Gemfile /mya/Gemfile
COPY Gemfile.lock /mya/Gemfile.lock
WORKDIR /mya

RUN bundle config set --local deployment 'true' && \
    bundle install

COPY . /mya
