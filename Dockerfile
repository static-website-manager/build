FROM ruby:2.2.3
RUN apt-get update -qq && apt-get install -y build-essential git nodejs
ENV home /build
RUN mkdir $home
WORKDIR $home
COPY Gemfile $home/Gemfile
COPY Gemfile.lock $home/Gemfile.lock
RUN bundle install
COPY . $home
RUN addgroup --system --gid 1448 git
RUN adduser --system --uid 1448 --ingroup git git
USER git
