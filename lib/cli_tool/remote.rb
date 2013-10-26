module CliTool
  module Remote
    class WaitingForSSH < StandardError; end;
    class Failure < StandardError; end;

    class Script < String
      def <<(script)
        script = script.strip + ';' unless script.match(/;$/)
        script = Script.new(script)
        super("#{script}\n")
      end

      def prepend(script)
        script = script.strip + ';' unless script.match(/;$/)
        script = Script.new(script)
        super("#{script}\n")
      end
    end

    def self.included(base)
      base.__send__(:include, ::CliTool::StdinOut)
      base.__send__(:include, ::CliTool::OptionParser)
      base.__send__(:include, ::CliTool::SoftwareDependencies)
      base.extend(ClassMethods)
      base.software(:ssh, :nc)
      base.options host: :required,
        identity: :required,
        debug: :none,
        user: {
          dependency: :required,
          default: %x{whoami}.strip
        },
        port: {
          dependency: :required,
          default: '22'
        }
    end

    def script(script = nil, sudo = false, sudouser = nil)
      @_script ||= Script.new
      return Script.new(@_script.strip) if script.nil?
      return @_script = Script.new if script == :reset
      @_script << (sudo == :sudo ? %{sudo su -l -c "#{script.strip.gsub('"','\"')}" #{sudouser}} : script).strip
    end

    def script_exec
      wait4ssh

      command =[ "ssh -t -t" ]
      command << "-I #{@identity}" if @identity
      command << "-p #{@port}" if @port
      command << "#{@user}@#{@host}"
      command << "<<-SCRIPT\n#{script}\nexit;\nSCRIPT"
      command  = command.join(' ')
      script :reset

      puts("Running Remotely:\n#{command}\n", [:blue, :white_bg])

      system(command)

      unless $?.success?
        raise Failure, "Error running \"#{command}\" on #{@host} exited with code #{$?.to_i}."
      end
    end

    def aptget(action = :update, *software)
      software = software.map(&:to_s).join(' ')
      script "apt-get #{action} -q -y --force-yes #{software}", :sudo
    end

    def aptkeyadd(*keys)
      keys = keys.map(&:to_s).join(' ')
      script "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys #{keys}", :sudo
    end

    def restart
      script :reset
      script "shutdown -r now &", :sudo
      script_exec

      # Let the server shutdown
      sleep 5
    end

    def adduser(user, system = false)
      script "adduser --disabled-password --quiet --gecos '' #{user}".squeeze(' '), :sudo
    end

    def wait4ssh
      _retry ||= false
      %x{nc -z #{@host} #{@port}}
      raise WaitingForSSH unless $?.success?
      puts("\nSSH is now available!", :green) if _retry
    rescue WaitingForSSH
      print "Waiting for ssh..." unless _retry
      _retry = true
      print '.'
      sleep 2
      retry
    end

    module ClassMethods

      # Create the options array
      def software(*soft)
        @@software ||= []

        # If no software dependencies were passed then return
        return @@software.uniq unless soft

        # Find missing software
        missing = []
        soft.each do |app|
          %x{which #{app}}
          missing << app unless $?.success?
        end

        # Raise if there were any missing software's
        unless missing.empty?
          missing = missing.join(', ')
          raise CliTool::MissingDependencies,
            %{The required software packages "#{missing}" could not be found in your $PATH.}
        end

        # Append to the software list
        @@software = @@software.concat(soft).uniq
      end
    end
  end
end
