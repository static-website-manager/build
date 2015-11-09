require_relative 'jekyll_build'

class BuildServer
  def call(env)
    request = Rack::Request.new(env)

    build_options = [
      request.params['website_id'],
      request.params['branch_name'],
      request.params['bucket_name'],
    ]

    case request.path
    when '/jekyll'
      puts "Starting Jekyll Build Job with options #{build_options}"
      respond_with *JekyllBuild.perform(*build_options)
    else
      puts "No Command Found"
      respond_with 404, 'Command Not Found'
    end
  end

  private

  def respond_with(status, body)
    [status, {'Content-Type' => 'text/html' }, [body]]
  end
end
