#This resource is created the parent :user_factory resource


module OmfRc::ResourceProxy::User
  include OmfRc::ResourceProxyDSL

  require 'omf_common/exec_app'

  register_proxy :user, :create_by => :user_factory

  utility :common_tools
  utility :platform_tools

  property :username
  property :app_id, :default => nil
  property :binary_path, :default => '/usr/sbin/useradd'
  property :map_err_to_out, :default => false

  configure :cert do |res, value|
    #puts "CERTIFICATE #{value.inspect}"
    path = "/home/#{res.property.username}/.omf/"
    unless File.directory?(path)#create the directory if it doesn't exist (it will never exist)
      FileUtils.mkdir_p(path)
    end

    File.write("#{path}/cert.pem", value)
  end

  configure :auth_keys do |res, value|
    File.open("/home/#{res.property.username}/.ssh/authorized_keys", 'w') do |file|
      value.each do |v|
        file.puts v
      end
    end
  end

  #hook :before_ready do |user|
    #define_method("on_app_event") { |*args| process_event(self, *args) }
  #end

  hook :after_initial_configured do |user|
    user.property.app_id = user.hrn.nil? ? user.uid : user.hrn

    ExecApp.new(user.property.app_id, user.build_command_line, user.property.map_err_to_out) do |event_type, app_id, msg|
      user.process_event(user, event_type, app_id, msg)
    end
  end

  # This method processes an event coming from the application instance, which
  # was started by this Resource Proxy (RP). It is a callback, which is usually
  # called by the ExecApp class in OMF
  #
  # @param [AbstractResource] res this RP
  # @param [String] event_type the type of event from the app instance
  #                 (STARTED, DONE.OK, DONE.ERROR, STDOUT, STDERR)
  # @param [String] app_id the id of the app instance
  # @param [String] msg the message carried by the event
  #
  def process_event(res, event_type, app_id, msg)
      logger.info "App Event from '#{app_id}' - #{event_type}: '#{msg}'"
      if event_type == 'EXIT'
        if msg == 0 #only when user creation succeeds, create a new public key and save it to /home/username/.ssh/
                    #then inform with the appropriate msg, and give the pub key
          key = OpenSSL::PKey::RSA.new(2048)

          pub_key = key.public_key

          path = "/home/#{res.property.username}/.ssh/"
          unless File.directory?(path)#create the directory if it doesn't exist (it will never exist)
            FileUtils.mkdir_p(path)
          end

          File.write("#{path}/pub_key.pem", pub_key.to_pem)
          File.write("#{path}/key.pem", key.to_pem)

          res.inform(:status, {
                        status_type: 'APP_EVENT',
                        event: event_type.to_s.upcase,
                        app: app_id,
                        exit_code: msg,
                        msg: msg,
                        uid: res.uid, # do we really need this? Should be identical to 'src'
                        pub_key: pub_key
                      }, :ALL)
        else #if msg!=0 then the application failed to complete
          path = "/home/#{res.property.username}/.ssh/"
          if File.exists?("#{path}/pub_key.pem") && File.exists?("#{path}/key.pem")#if keys exist just read the pub_key for the inform
            file = File.open("#{path}/pub_key.pem", "rb")
            pub_key = file.read
            file.close
          else #if keys do not exist create them and then inform
            key = OpenSSL::PKey::RSA.new(2048)

            pub_key = key.public_key

            path = "/home/#{res.property.username}/.ssh/"
            unless File.directory?(path)#create the directory if it doesn't exist (it will never exist)
              FileUtils.mkdir_p(path)
            end

            File.write("#{path}/pub_key.pem", pub_key.to_pem)
            File.write("#{path}/key.pem", key.to_pem)
          end
          res.inform(:status, {
                        status_type: 'APP_EVENT',
                        event: event_type.to_s.upcase,
                        app: app_id,
                        exit_code: msg,
                        msg: msg,
                        uid: res.uid, # do we really need this? Should be identical to 'src'
                        pub_key: pub_key
                      }, :ALL)
        end
      else
        res.inform(:status, {
                      status_type: 'APP_EVENT',
                      event: event_type.to_s.upcase,
                      app: app_id,
                      msg: msg,
                      uid: res.uid
                    }, :ALL)
      end
  end

  # Build the command line, which will be used to add a new user.
  #
  work('build_command_line') do |res|
    cmd_line = "env -i " # Start with a 'clean' environment
    cmd_line += res.property.binary_path + " " # the /usr/sbin/useradd
    cmd_line += " -m -s /bin/bash #{res.property.username}"  # the username, -m for adding folder -s for default shell to /bin/bash, removed -d /home/#{res.property.username}
    cmd_line
  end
end
