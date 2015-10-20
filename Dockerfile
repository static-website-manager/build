FROM ruby:2.2.3
RUN apt-get update -qq && apt-get install -y build-essential nodejs python-pip
RUN pip install awscli
ENV home /build
RUN mkdir $home
WORKDIR $home
ADD Gemfile $home/Gemfile
ADD Gemfile.lock $home/Gemfile.lock
RUN bundle install
EXPOSE 9292
ADD . $home
