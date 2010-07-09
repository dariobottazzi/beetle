# Redis convenience and compatibility layer
class Redis #:nodoc:
  def self.from_server_string(server_string, options = {})
    host, port = server_string.split(':')
    options = {:host => host, :port => port}.update(options)
    new(options)
  end

  module RoleSupport
    def info_with_rescue
      info
    rescue Exception
      {}
    end

    def available?
      info_with_rescue != {}
    end

    def role
      info_with_rescue["role"] || "unknown"
    end

    def master?
      role == "master"
    end

    def slave?
      role == "slave"
    end

    def slave_of?(host, port)
      info = info_with_rescue
      info["role"] == "slave" && info["master_host"] == host && info["master_port"] == port.to_s
    end
  end

end

if Redis::VERSION >= "2.0.3"

  class Redis #:nodoc:
    # Redis 2 removed some useful methods. add them back.
    def host; @client.host; end
    def port; @client.port; end
    def server; "#{host}:#{port}"; end

    include Redis::RoleSupport

    def master!
      slaveof("no", "one")
    end

    def slave_of!(host, port)
      slaveof(host, port)
    end
  end

  class Redis::Client #:nodoc:
    protected
    def connect_to(host, port)
      if @timeout != 0 and Redis::Timer
        begin
          Redis::Timer.timeout(@timeout){ @sock = TCPSocket.new(host, port) }
        rescue Timeout::Error
          @sock = nil
          raise Timeout::Error, "Timeout connecting to the server"
        end
      else
        @sock = TCPSocket.new(host, port)
      end

      @sock.setsockopt Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1

      # If the timeout is set we set the low level socket options in order
      # to make sure a blocking read will return after the specified number
      # of seconds. This hack is from memcached ruby client.
      self.timeout = @timeout

    rescue Errno::ECONNREFUSED
      raise Errno::ECONNREFUSED, "Unable to connect to Redis on #{host}:#{port}"
    end
  end

elsif Redis::VERSION >= "1.0.7" && Redis::VERSION < "2.0.0"

  class Redis::Client #:nodoc:
    attr_reader :host, :port

    include Redis::RoleSupport

    def master!
      slaveof("no one")
    end

    def slave_of!(host, port)
      slaveof("#{host} #{port}")
    end

    # monkey patch the connect_to method so that it times out faster
    def connect_to(host, port)
      # We support connect_to() timeout only if system_timer is availabe
      # or if we are running against Ruby >= 1.9
      # Timeout reading from the socket instead will be supported anyway.
      if @timeout != 0 and Redis::Timer
        begin
          Redis::Timer.timeout(@timeout){ @sock = TCPSocket.new(host, port) }
        rescue Timeout::Error
          @sock = nil
          raise Timeout::Error, "Timeout connecting to the server"
        end
      else
        @sock = TCPSocket.new(host, port)
      end

      @sock.setsockopt Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1

      # If the timeout is set we set the low level socket options in order
      # to make sure a blocking read will return after the specified number
      # of seconds. This hack is from memcached ruby client.
      set_socket_timeout!(@timeout) if @timeout

    rescue Errno::ECONNREFUSED
      raise Errno::ECONNREFUSED, "Unable to connect to Redis on #{host}:#{port}"
    end
  end

else

  raise "Your redis-rb version is not supported!"

end