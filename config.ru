require 'open3'

class BuildServer
  class GitConfigError < StandardError ; end
  class GitPullError < StandardError ; end
  class JekyllBuildError < StandardError ; end
  class S3SyncError < StandardError ; end

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
      respond(404, 'Command Not Found')
    end
  end

  def jekyll(website_id, deployment_id, branch_name, bucket_name)
    begin
      raise ArgumentError unless website_id.match(/\A\d{1,9}\z/)
      raise ArgumentError unless deployment_id.match(/\A\d{1,9}\z/)
      branch_name = perform("git check-ref-format --branch #{branch_name}", raise_with: ArgumentError)
      raise ArgumentError unless bucket_name.match(/\A[0-9a-f]{8}\.staticwebsitemanager\z/)

      repository_pathname = Pathname.new("/repos/#{website_id}.git")
      deployment_pathname = Pathname.new("/sites/#{deployment_id}")

      raise ArgumentError unless repository_pathname.exist?
      raise ArgumentError unless deployment_pathname.exist?

      perform("git config user.email \"support@staticwebsitemanager.com\"", chdir: deployment_pathname.to_s, raise_with: GitConfigError)
      perform("git config user.name \"Static Website Manager\"", chdir: deployment_pathname.to_s, raise_with: GitConfigError)
      perform("git pull #{repository_pathname} #{branch_name}", chdir: deployment_pathname.to_s, raise_with: GitPullError)
      perform("git pull #{repository_pathname} #{branch_name}", chdir: deployment_pathname.to_s, raise_with: GitPullError)
      perform("jekyll build --safe --source #{deployment_pathname} --destination #{deployment_pathname.join('_site')}", raise_with: JekyllBuildError)
      perform("aws s3 sync --acl public-read --delete #{deployment_pathname.join('_site')} s3://#{bucket_name}", raise_with: S3SyncError)

      respond(200, 'Website successfully generated and synced')
    rescue GitConfigError
      respond(500, 'Git Config Error: There was a problem configuring the deployment repository.')
    rescue GitPullError
      respond(500, 'Git Pull Error: There was a problem pulling from website repository')
    rescue JekyllBuildError
      respond(500, 'Jekyll Build Error: There was a problem compiling your website')
    rescue S3SyncError
      respond(500, 'S3 Sync Error: There was a problem syncing your website')
    rescue
      respond(500, 'There was a problem generating your website')
    end
  end

  private

  def perform(command, args = {})
    raise_with = args.delete(:raise_with)
    stdin, stdout, stderr, wait_thread = Open3.popen3(command, args)
    stdin.close
    stdout_log = stdout.read
    stdout.close
    stderr_log = stderr.read
    stderr.close

    if wait_thread.value.success?
      stdout_log
    else
      raise raise_with, stderr
    end
  end

  def respond(status, body)
    [status, {'Content-Type' => 'text/html'}, [body]]
  end
end

run BuildServer.new
