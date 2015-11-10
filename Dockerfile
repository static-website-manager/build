FROM ruby:2.2.3
RUN apt-get update -qq && apt-get install -y build-essential git nodejs python-pip
RUN pip install awscli
ENV home /build
RUN mkdir $home
WORKDIR $home
COPY Gemfile $home/Gemfile
COPY Gemfile.lock $home/Gemfile.lock
RUN bundle install
COPY . $home
RUN adduser --system --uid 1448 --ingroup root git
USER git
