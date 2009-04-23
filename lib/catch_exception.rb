# CatchException
module CatchException

  IGNORE_DEFAULT = ['ActiveRecord::RecordNotFound',
                    'ActionController::RoutingError',
                    'ActionController::InvalidAuthenticityToken',
                    'CGI::Session::CookieStore::TamperedWithCookie',
                    'ActionController::UnknownAction']

  # Some of these don't exist for Rails 1.2.*, so we have to consider that.
  IGNORE_DEFAULT.map!{|e| eval(e) rescue nil }.compact!
  IGNORE_DEFAULT.freeze

  IGNORE_USER_AGENT_DEFAULT = []

  class << self
    attr_accessor :host, :port, :secure, :api_key, :http_open_timeout, :http_read_timeout,
                  :proxy_host, :proxy_port, :proxy_user, :proxy_pass, :namespase

    def backtrace_filters
      @backtrace_filters ||= []
    end

    # Takes a block and adds it to the list of backtrace filters. When the filters
    # run, the block will be handed each line of the backtrace and can modify
    # it as necessary. For example, by default a path matching the RAILS_ROOT
    # constant will be transformed into "[RAILS_ROOT]"
    def filter_backtrace &block
      self.backtrace_filters << block
    end
		
		def namespase
			@namespase ||= 'localhost'
		end
		
    # The port on which your Hoptoad server runs.
    def port
      @port || (secure ? 443 : 80)
    end

    # The host to connect to.
    def host
      @host ||= 'localhost'
    end

    # The HTTP open timeout (defaults to 2 seconds).
    def http_open_timeout
      @http_open_timeout ||= 2
    end

    # The HTTP read timeout (defaults to 5 seconds).
    def http_read_timeout
      @http_read_timeout ||= 5
    end

    # Returns the list of errors that are being ignored. The array can be appended to.
    def ignore
      @ignore ||= (CatchException::IGNORE_DEFAULT.dup)
      @ignore.flatten!
      @ignore
    end

    # Sets the list of ignored errors to only what is passed in here. This method
    # can be passed a single error or a list of errors.
    def ignore_only=(names)
      @ignore = [names].flatten
    end

    # Returns the list of user agents that are being ignored. The array can be appended to.
    def ignore_user_agent
      @ignore_user_agent ||= (CatchException::IGNORE_USER_AGENT_DEFAULT.dup)
      @ignore_user_agent.flatten!
      @ignore_user_agent
    end

    # Sets the list of ignored user agents to only what is passed in here. This method
    # can be passed a single user agent or a list of user agents.
    def ignore_user_agent_only=(names)
      @ignore_user_agent = [names].flatten
    end

    # Returns a list of parameters that should be filtered out of what is sent to Hoptoad.
    # By default, all "password" attributes will have their contents replaced.
    def params_filters
      @params_filters ||= %w(password)
    end

    def environment_filters
      @environment_filters ||= %w()
    end

    # Call this method to modify defaults in your initializers.
    #
    # CatchException.configure do |config|
    #   config.api_key = '1234567890abcdef'
    #   config.secure  = false
    # end
    #
    # NOTE: secure connections are not yet supported.
    def configure
      add_default_filters
      yield self
      if defined?(ActionController::Base) && !ActionController::Base.include?(CatchException::Catcher)
        ActionController::Base.send(:include, CatchException::Catcher)
      end
    end

    def protocol #:nodoc:
      secure ? "https" : "http"
    end

    def url #:nodoc:
      URI.parse("#{protocol}://#{host}:#{port}/issues_create/")
    end

    def default_notice_options #:nodoc:
      {
        :api_key       => CatchException.api_key,
        :error_message => 'Notification',
        :backtrace     => caller,
        :request       => {},
        :session       => {},
        :environment   => ENV.to_hash
      }
    end

    # You can send an exception manually using this method, even when you are not in a
    # controller. You can pass an exception or a hash that contains the attributes that
    # would be sent to Hoptoad:
    # * api_key: The API key for this project. The API key is a unique identifier that Hoptoad
    #   uses for identification.
    # * error_message: The error returned by the exception (or the message you want to log).
    # * backtrace: A backtrace, usually obtained with +caller+.
    # * request: The controller's request object.
    # * session: The contents of the user's session.
    # * environment: ENV merged with the contents of the request's environment.
    def notify(notice = {})
      Sender.new.catch_exception(notice)
    end

    def add_default_filters
      self.backtrace_filters.clear

      filter_backtrace do |line|
        line.gsub(/#{RAILS_ROOT}/, "[RAILS_ROOT]")
      end

      filter_backtrace do |line|
        line.gsub(/^\.\//, "")
      end

      filter_backtrace do |line|
        if defined?(Gem)
          Gem.path.inject(line) do |line, path|
            line.gsub(/#{path}/, "[GEM_ROOT]")
          end
        end
      end

      filter_backtrace do |line|
        line if line !~ /lib\/#{File.basename(__FILE__)}/
      end
    end
  end
end
