class BuildServer
  def call(env)
    request = Rack::Request.new(env)

    if request.post? && request.path == '/jekyll'
      jekyll(
        request.params['website_id'],
        request.params['deployment_id'],
        request.params['branch_name'],
        request.params['bucket_name'],
      )
    else
      respond(404, '')
    end
  end

  def jekyll(website_id, deployment_id, branch_name, bucket_name)
    begin
      raise ArgumentError unless website_id.match(/\A\d{1,9}\z/) && deployment_id.match(/\A\d{1,9}\z/)
      # raise ArgumentError if `git check-ref-format #{branch_name} exits poorly

      repository_pathname = Pathname.new("/repos/#{website_id}.git")
      deployment_pathname = Pathname.new("/sites/#{deployment_id}")

      raise ArgumentError unless repository_pathname.exist?
      raise ArgumentError unless deployment_pathname.exist?

      `cd #{deployment_pathname}; git pull #{repository_pathname} #{branch_name}`
      `jekyll build --safe --source #{deployment_pathname} --destination #{deployment_pathname.join('_site')}`
      `aws s3 sync --acl public-read #{deployment_pathname.join('_site')} s3://#{bucket_name}`

      respond(200, 'ok')
    rescue
      respond(500, 'oops')
    end
  end

  private

  def respond(status, body)
    [status, {'Content-Type' => 'text/html'}, [body]]
  end
end

run BuildServer.new
