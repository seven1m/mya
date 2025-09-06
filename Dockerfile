FROM ruby:3.4-trixie

RUN apt-get update && \
  apt-get install -y -q build-essential clang wget gpg && \
  wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /usr/share/keyrings/llvm-snapshot.gpg && \
  echo "deb [signed-by=/usr/share/keyrings/llvm-snapshot.gpg] http://apt.llvm.org/trixie/ llvm-toolchain-trixie-20 main" >> /etc/apt/sources.list.d/llvm.list && \
  apt-get update && \
  apt-get install -y -q llvm-20-dev

COPY Gemfile /mya/Gemfile
COPY Gemfile.lock /mya/Gemfile.lock
WORKDIR /mya

RUN bundle config set --local deployment 'true' && \
  bundle install

COPY . /mya

ENTRYPOINT ["./bin/mya"]
