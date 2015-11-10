require 'fileutils'
require 'open3'
require 'pathname'

class JekyllBuild
  class GitCloneError < StandardError ; end
  class JekyllBuildError < StandardError ; end
  class S3SyncError < StandardError ; end

  def self.perform(*args)
    new(*args).perform
  end

  def initialize(website_id, branch_name, bucket_name)
    raise ArgumentError unless website_id.match(/\A\d{1,9}\z/)
    repository_pathname = Pathname.new("/repos/#{website_id}.git")
    raise ArgumentError unless repository_pathname.exist?
    branch_name = popen("git check-ref-format --branch #{branch_name}", raise_with: ArgumentError)
    raise ArgumentError unless bucket_name.match(/\A[0-9a-f]{8}\.staticwebsitemanager\z/)

    @repository_pathname = repository_pathname
    @branch_name = branch_name
    @bucket_name = bucket_name
  end

  def perform
    clone_path = Pathname.new(File.join('/tmp', "clone_#{rand(1000)}_#{Time.now.to_i}"))

    begin
      # Unsure why this will not work, as it does through bash, sh, and bash->irb
      # popen("git clone --branch #@branch_name --depth 1 file://#@repository_pathname #{clone_path}", raise_with: GitCloneError)
      popen("git clone file://#@repository_pathname #{clone_path}", raise_with: GitCloneError)
      popen("git checkout #@branch_name", chdir: clone_path, raise_with: GitCloneError)
      popen("jekyll build --safe --source #{clone_path} --destination #{clone_path.join('_site')}", raise_with: JekyllBuildError)
      popen("aws s3 sync --acl public-read --delete #{clone_path.join('_site')} s3://#@bucket_name", raise_with: S3SyncError)

      [200, 'Website Successfully Generated and Synced.']
    rescue GitCloneError
      [500, 'Git Error: There was a problem cloning your repository.']
    rescue JekyllBuildError
      [500, 'Build Error: There was a problem generating your static website.']
    rescue S3SyncError
      [500, 'Sync Error: There was a publishing your static website.']
    ensure
      FileUtils.rm_rf(clone_path)
    end
  end

  def popen(command, args = {})
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
      raise raise_with, stderr_log
    end
  end
end
