require 'digest'
require 'fileutils'
require 'open3'
require 'pathname'

class JekyllBuild
  class GitCloneError < StandardError ; end
  class JekyllBuildError < StandardError ; end

  def self.perform(*args)
    new(*args).perform
  end

  def initialize(website_id, branch_name, commit_id)
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

      [200, 'Website Successfully Compiled.']
    rescue GitCloneError
      [500, 'Git Error: There was a problem cloning your repository.']
    rescue JekyllBuildError
      [500, 'Build Error: There was a problem compiling your static website.']
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
