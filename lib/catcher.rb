# Include this module in Controllers in which you want to be notified of errors.
module CatchException
  module Catcher

    def self.included(base) #:nodoc:
      if base.instance_methods.include? 'rescue_action_in_public' and !base.instance_methods.include? 'rescue_action_in_public_without_catch'
        base.send(:alias_method, :rescue_action_in_public_without_catch, :rescue_action_in_public)
        base.send(:alias_method, :rescue_action_in_public, :rescue_action_in_public_with_catch)
      end
    end

    # Overrides the rescue_action method in ActionController::Base, but does not inhibit
    # any custom processing that is defined with Rails 2's exception helpers.
    def rescue_action_in_public_with_catch(exception)
      catch_exception(exception) unless ignore?(exception) || ignore_user_agent?
      rescue_action_in_public_without_catch(exception)
    end

    # This method should be used for sending manual notifications while you are still
    # inside the controller. Otherwise it works like CatchException.notify.
    def catch_exception(hash_or_exception)
      if public_environment?
        notice = normalize_notice(hash_or_exception)
        notice = clean_notice(notice)
        send_to_server(notice)
      end
    end

    # Returns the default logger or a logger that prints to STDOUT. Necessary for manual
    # notifications outside of controllers.
    def logger
      ActiveRecord::Base.logger
    rescue
      @logger ||= Logger.new(STDERR)
    end

    private

    def public_environment? #nodoc:
      defined?(RAILS_ENV) and !['development', 'test'].include?(RAILS_ENV)
    end

    def ignore?(exception) #:nodoc:
      ignore_these = CatchException.ignore.flatten
      ignore_these.include?(exception.class) || ignore_these.include?(exception.class.name)
    end

    def ignore_user_agent? #:nodoc:
      CatchException.ignore_user_agent.flatten.any? { |ua| ua === request.user_agent }
    end

    def exception_to_data(exception) #:nodoc:
      data = {
        :api_key       => CatchException.api_key,
        :error_class   => exception.class.name,
        :error_message => "#{exception.class.name}: #{exception.message}",
        :backtrace     => exception.backtrace.join("\n"),
        :environment   => '', #pp_hash(ENV.to_hash),
        :namespase		 => CatchException.namespase
      }

      if self.respond_to? :request
      	host = (request.env["HTTP_X_FORWARDED_HOST"] || request.env["HTTP_HOST"])
      	data[:request] = "* URL       : #{request.protocol}#{host}#{request.request_uri}
													* IP address: #{request.env["HTTP_X_FORWARDED_FOR"] || request.env["REMOTE_ADDR"]}
													* Parameters: #{pp_hash request.parameters.to_hash}
													* Rails root: #{File.expand_path(RAILS_ROOT)}"
													
        #data[:environment].merge!(request.env.to_hash)
        max = request.env.keys.max { |a,b| a.length <=> b.length }
   			request.env.keys.sort.each do |key|
   				data[:environment] += "* %-*s: %s \n" % [max.length, key, pp_param(request.env[key])]
   			end
       	data[:environment] += "* Process: #{$$}\n"
				data[:environment] += "* Server : #{`hostname -s`.chomp}\n"
      end

      if self.respond_to? :session
      	data[:session] = "* session id: #{session.instance_variable_get("@session_id")}
													* data: #{PP.pp(session.instance_variable_get("@data"),"").gsub(/\n/, "\n  ").strip}"
      end

      data
    end

    def normalize_notice(notice) #:nodoc:
      case notice
      when Hash
        CatchException.default_notice_options.merge(notice)
      when Exception
        CatchException.default_notice_options.merge(exception_to_data(notice))
      end
    end

    def clean_notice(notice) #:nodoc:
      notice[:backtrace] = clean_catch_backtrace(notice[:backtrace])
      if notice[:request].is_a?(Hash) && notice[:request][:params].is_a?(Hash)
        notice[:request][:params] = filter_parameters(notice[:request][:params]) if respond_to?(:filter_parameters)
        notice[:request][:params] = clean_catch_params(notice[:request][:params])
      end
      if notice[:environment].is_a?(Hash)
        notice[:environment] = filter_parameters(notice[:environment]) if respond_to?(:filter_parameters)
        notice[:environment] = clean_catch_environment(notice[:environment])
      end
      clean_non_serializable_data(notice)
    end

    def send_to_server(data) #:nodoc:
      url = CatchException.url
			req = Net::HTTP::Post.new(url.path)
			req.set_form_data(data)
			#req.basic_auth 'api_key', CatchException.api_key

      response = begin
                   #http.post(url.path, stringify_keys(data).to_yaml, headers)
                   Net::HTTP.new(url.host, url.port).start {|http| http.request(req) }
                 rescue SocketError, TimeoutError => e
                   logger.error "Timeout while contacting the CatchException server." if logger
                   nil
                 end

      case response
      when Net::HTTPSuccess then
        logger.info "CatchException Success: #{response.class}" if logger
      else
        logger.error "CatchException Failure: #{response.class}\n#{response.body if response.respond_to? :body}" if logger
      end
    end

    def clean_catch_backtrace(backtrace) #:nodoc:
      if backtrace.to_a.size == 1
        backtrace = backtrace.to_a.first.split(/\n\s*/)
      end

      filtered = backtrace.to_a.map do |line|
        CatchException.backtrace_filters.inject(line) do |line, proc|
          proc.call(line)
        end
      end

      filtered.compact
    end

    def clean_catch_params(params) #:nodoc:
      params.each do |k, v|
        params[k] = "[FILTERED]" if CatchException.params_filters.any? do |filter|
          k.to_s.match(/#{filter}/)
        end
      end
    end

    def clean_catch_environment(env) #:nodoc:
      env.each do |k, v|
        env[k] = "[FILTERED]" if CatchException.environment_filters.any? do |filter|
          k.to_s.match(/#{filter}/)
        end
      end
    end

    def clean_non_serializable_data(notice) #:nodoc:
      notice.select{|k,v| serializable?(v) }.inject({}) do |h, pair|
        h[pair.first] = pair.last.is_a?(Hash) ? clean_non_serializable_data(pair.last) : pair.last
        h
      end
    end

    def serializable?(value) #:nodoc:
      value.is_a?(Fixnum) || 
      value.is_a?(Array)  || 
      value.is_a?(String) || 
      value.is_a?(Hash)   || 
      value.is_a?(Bignum)
    end

    def stringify_keys(hash) #:nodoc:
      hash.inject({}) do |h, pair|
        h[pair.first.to_s] = pair.last.is_a?(Hash) ? stringify_keys(pair.last) : pair.last
        h
      end
    end
    
    def pp_param(value)
    	return pp_hash(value) if value.is_a?(Hash)
    	return value.join('; ') if value.is_a?(Array)
    	value.to_s.strip
    end
    
    def pp_hash(hash)
    	str = []
    	hash.each do |k, v|
    		str << "#{k.inspect} => #{v.inspect}"
    	end
    	"{" + str.join(', ') + "}"
    end

  end
end
