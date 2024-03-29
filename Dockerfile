FROM ubuntu:23.10

RUN apt-get update && \
  apt-get install -y -q build-essential ruby ruby-dev git wget lsb-release software-properties-common gnupg clang && \
  wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && ./llvm.sh 17 && \
  gem install bundler

RUN ln -s /usr/bin/lli-17 /usr/bin/lli

COPY Gemfile /mya/Gemfile
COPY Gemfile.lock /mya/Gemfile.lock
WORKDIR /mya

RUN bundle config set --local deployment 'true' && \
  bundle install

COPY . /mya
