FROM ruby:3.3-bullseye

RUN apt-get update && \
  apt-get install -y -q build-essential lsb-release software-properties-common gnupg clang && \
  wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && ./llvm.sh 18

COPY Gemfile /mya/Gemfile
COPY Gemfile.lock /mya/Gemfile.lock
WORKDIR /mya

RUN bundle config set --local deployment 'true' && \
  bundle install

COPY . /mya
