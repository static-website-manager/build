require 'digest'
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

  def initialize(website_id, branch_name, commit_id, aws_s3_bucket = nil, aws_region = nil, aws_access_key_id = nil, aws_secret_access_key = nil)
    raise ArgumentError unless website_id.match(/\A\d{1,9}\z/)
    repository_pathname = Pathname.new("/repos/#{website_id}.git")
    raise ArgumentError unless repository_pathname.exist?
    branch_name = popen("git check-ref-format --branch #{branch_name}", raise_with: ArgumentError).sub(/\n\z/, '')
    branch_sha = Digest::SHA1.hexdigest(branch_name)
    raise ArgumentError unless commit_id.match(/\A[0-9a-f]{40}\z/)

    @repository_pathname = repository_pathname
    @branch_name = branch_name
    @commit_id = commit_id
    @website_pathname = Pathname.new("/websites/#{website_id}/#{branch_sha}")
    @compiled_website_pathname = Pathname.new("/websites/#{website_id}/#{branch_sha}/_site")
    @compiled_website_version_pathname = Pathname.new("/websites/#{website_id}/#{branch_sha}/_site/.version")
    @aws_s3_bucket = aws_s3_bucket
    @aws_region = aws_region
    @aws_access_key_id = aws_access_key_id
    @aws_secret_access_key = aws_secret_access_key
  end

  def perform
    if @compiled_website_version_pathname.exist? && File.read(@compiled_website_version_pathname).sub(/\n\z/, '') == @commit_id
      return [304, 'Website Already Exists']
    end

    begin
      if @website_pathname.exist?
        popen("git pull origin #@branch_name", chdir: @website_pathname, raise_with: GitCloneError)
      else
        # Unsure why this will not work, as it does through bash, sh, and bash->irb
        # popen("git clone --branch #@branch_name --depth 1 file://#@repository_pathname #@website_pathname", raise_with: GitCloneError)
        popen("git clone file://#@repository_pathname #@website_pathname", raise_with: GitCloneError)
        popen("git checkout #@branch_name", chdir: @website_pathname, raise_with: GitCloneError)
      end

      popen("jekyll build --drafts --future --incremental --safe --source #@website_pathname --destination #@compiled_website_pathname", raise_with: JekyllBuildError)
      popen("echo #@commit_id > #@compiled_website_version_pathname")

      if [@aws_access_key_id, @aws_secret_access_key, @aws_region, @aws_s3_bucket].map(&:to_s).none?(&:empty?)
        $stdout.puts "Starting aws s3 sync to #@aws_s3_bucket"
        popen("AWS_ACCESS_KEY_ID=#@aws_access_key_id AWS_SECRET_ACCESS_KEY=#@aws_secret_access_key AWS_DEFAULT_REGION=#@aws_region aws s3 sync --acl public-read --delete #@compiled_website_pathname s3://#@aws_s3_bucket", raise_with: S3SyncError)
      end

      [200, 'Website Successfully Compiled.']
    rescue GitCloneError
      [500, 'Git Error: There was a problem cloning your repository.']
    rescue JekyllBuildError
      [500, 'Build Error: There was a problem compiling your static website.']
    rescue S3SyncError
      [500, 'Sync Error: There was a problem deploying your static website to AWS S3.']
    rescue Exception => e
      $stderr.puts e
      raise e
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
