class BuildServer
  def call(env)
    request = Rack::Request.new(env)

    if request.post? && request.path == '/jekyll'
      jekyll request.params['website_id'], request.params['deployment_id'], request.params['branch_name'], request.params['bucket_name']
    else
      ['404', {'Content-Type' => 'text/html'}, ['']]
    end
  end

  def jekyll(website_id, deployment_id, branch_name, bucket_name)
    begin
      raise ArgumentError unless website_id.match(/\A\d{1,9}\z/) && deployment_id.match(/\A\d{1,9}\z/)
      # raise ArgumentError if `git check-ref-format #{branch_name} exits poorly

      repository_pathname = Pathname.new("/repos/#{website_id}.git")
      deployment_pathname = Pathname.new("/sites/#{deployment_id}")

      raise ArgumentError unless repository_pathname.exist?

      if deployment_pathname.exist?
        `cd #{deployment_pathname}; git pull #{repository_pathname} #{branch_name}`
      else
        `git clone -b #{branch_name} #{repository_pathname} #{deployment_pathname}`
      end

      `cd #{deployment_pathname}; jekyll build`
      `aws s3 sync --acl public-read #{deployment_pathname.join('_site')} s3://#{bucket_name}`

      ['200', {'Content-Type' => 'text/html'}, ['ok']]
    rescue
      ['500', {'Content-Type' => 'text/html'}, ['oops']]
    end
  end
end

run BuildServer.new
