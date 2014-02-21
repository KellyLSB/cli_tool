module CliTool
  module Remote
    class WaitingForSSH < StandardError; end;
    class Failure < StandardError; end;

    class Script
      include CliTool::StdinOut
      attr_accessor :commands
      attr_accessor :environment

      def initialize
        @environment = {}
        @commands    = []
        @apt         = {}
        @remote_installed = 0
      end
      alias reset initialize

      ################
      #= User Tools =#
      ################

      # def adduser(user, system = false)
      #   script "adduser --disabled-password --quiet --gecos '' #{user}".squeeze(' '), :sudo
      # end

      ###############
      #= Apt Tools =#
      ###############

      def install(*packages); apt(:install, *packages) end

      def purge(*packages);   apt(:purge, *packages)   end

      def remove(*packages);  apt(:remove, *packages)  end

      def update;             apt(:update)             end

      def upgrade;            apt(:upgrade)            end

      def upgrade!;           apt(:'dist-upgrade')     end

      def aptkey(*keys)
        keyserver = yield if block_given?
        keyserver ||= 'keyserver.ubuntu.com'
        exec("apt-key adv --keyserver #{keyserver} --recv-keys #{keys.join(' ')}", :sudo)
        self
      end

      ##########
      #= DPKG =#
      ##########

      def if_installed?(*packages);     check_installed(true, *packages)  end

      def unless_installed?(*packages); check_installed(false, *packages) end

      def dpkg_install(*packages)
        packages.each do |package|
          exec("dpkg -i #{package}", :sudo)
        end
        self
      end

      def remote_install(*packages)
        @remote_installed = 0
        packages.each do
          @remote_installed += 1
          tmp = "#{Time.now.to_s}#{@remote_installed}.deb"
          curl(file, tmp, :sudo)
          dpkg_install(tmp)
          exec("rm -f #{tmp}", :sudo)
        end
        self
      end

      ###########
      #= Tools =#
      ###########

      def wget(from, to, sudo = false, sudouser = :root)
        install(:wget)
        exec("wget -O #{to} #{from}", sudo, sudouser)
        self
      end

      def curl(from, to, sudo = false, sudouser = :root)
        install(:curl)
        exec("curl -# -o #{to} #{from}", sudo, sudouser)
        self
      end

      def service(name, action)
        exec("service #{name} #{action}", :sudo)
      end

      ##########
      #= Exec =#
      ##########

      def exec(script, sudo = false, sudouser = :root)
        if File.exist?(script)
          script = File.read(script)
        end
        # Wrap the script in a sudoers block
        script  = %{sudo su -l -c "/bin/bash" #{sudouser || :root} <<-EOF\n#{script.rstrip}\nEOF} if sudo || sudo == :sudo
        @commands << script.rstrip
        self
      end

      def to_s(indent = 0)
        script = @environment.reduce([]).each do |out, (key, val)|
          out << %{#{(' ' * indent)}#{key.upcase}="#{val}"}
        end

        @commands.split(/\n/).reduce(script){ |out, x|  out << ((' ' * indent) + x) }.join("\n")
      end

      private

      def apt(command, *p, &b)
        @environment['DEBIAN_FRONTEND'] = 'noninteractive'
        return aptkey(*p, &b) if command == :key
        return if ((@apt[command] ||= []) - p).empty? && [:install, :purge, :remove].include?(command)
        ((@apt[command] ||= []) << p).flatten!
        exec(('apt-get #{command} -q -y --force-yes ' + p.map(&:to_s).join(' ')), :sudo)
        self
      end

      def check_installed(installed, *p)
        installed = installed ? '1' : '0'

        exec('if ' << packages.reduce([]) { |command, package|
          command << %{[ "$(dpkg -s #{package} > /dev/null 2>1 && echo '1' || echo '0')" == '#{installed}' ]}
        }.join(' && ') << "; then\n" << Script.new.__send__(:instance_exec, &block).to_s(2) << "\nfi")
        self
      end
    end

    def self.included(base)
      base.__send__(:include, ::Singleton)
      base.__send__(:alias_method, :new, :instance)
      base.__send__(:include, ::CliTool::StdinOut)
      base.__send__(:include, ::CliTool::OptionParser)
      base.__send__(:include, ::CliTool::SoftwareDependencies)
      base.extend(ClassMethods)
      base.software(:ssh, :nc)
      base.options({
        [:username, :user] => {
          default: %x{whoami}.strip,
          dependency: :required,
          short: :u,
          documentation: 'SSH username'
        },
        [:password, :pass] => {
          default: '22',
          dependency: :required,
          short: :p,
          documentation: 'SSH password (not implemented)'
        },
        identity: {
          dependency: :required,
          short: :i,
          documentation: 'SSH key to use'
        },
        host: {
          dependency: :required,
          short: :h,
          documentation: 'SSH host to connect to'
        },
        port: {
          default: '22',
          dependency: :required,
          short: :p,
          documentation: 'SSH port to connect on'
        },
        [:tags, :tag] => {
          dependency: :required,
          short: :t,
          documentation: 'Run tags (limit scripts to run)',
          preprocess: ->(tags) { tags.split(',').map{ |x| x.strip.to_sym } }
        },
        debug: :none
      })
    end

    # NEED SINGLETON OBJECT!!!

    class << self
      def script(options = {}, &block)
        script = Proc.new do |obj|
          run = true

          if obj[:tags]
            tags = (options[:tags] || []).concat([options[:tag]]).compact.flatten
            run = false if (kls.tags.map{ |x| "#{x}".strip.to_sym } & tags).empty?
          end

          if run # Do we want to run this script?
            build_script = Script.new
            build_script.__send__(:instance_exec, obj, &block)
            if options[:reboot] == true
              build_script.exec('shutdown -r now', :sudo)
              puts "Waiting for server reboot!"
              sleep 5
            elsif options[:shutdown] == true
              build_script.exec('shutdown -h now', :sudo)
              puts "Server shutdown requested!"
            end

            build_script
          else
            false # Don't run anything
          end
        end

        queue(script)
      end

      def shutdown!
        queue(Script.new.exec('shutdown -h now', :sudo))
      end

      def restart!
        queue(Script.new.exec('shutdown -r now', :sudo))
      end

      def   !(*a, &b)
        run(:run_suite!, *a, &b)
      end

      def custom!(*a, &b)
        Proc.new { |obj| obj.instance_exec(*a, &b) }
        false
      end

      private

      def queue(*items)
        return @@queue || [] if items.empty?
        items.map!{ |x| x.is_a?(Script) ? x.to_s : x }.flatten!
        ((@@queue ||= []) << x).flatten!
        self
      end
    end

    def export(dir = nil)
      self.class.queue.select{ |x| x.is_a?(String) }
    end

    def remote_exec!(script)
      ssh_cmd =[ 'ssh -t -t' ]
      ssh_cmd << "-I #{@identity}" if @identity
      ssh_cmd << "-p #{@port}"     if @port
      ssh_cmd << "#{@user}@#{@host}"
      ssh_cmd << "<<-SCRIPT\n#{script}\nexit;\nSCRIPT"

      if @debug
        message = "About to run remote process over ssh on #{@user}@#{@host}:#{@port}"
        puts message, :blue
        puts '#' * message.length, :blue
        puts script, :green
        puts '#' * message.length, :blue
        confirm "Should we continue?", :red
      end

      return false unless ssh_connection?

      system(ssh_cmd.join(' '))
      $?.success?
    end

    def run_suite!
      self.class.queue.each do |item|
        item = instance_exec(&item) if item.is_a?(Proc)
        remote_exec!(item) if item.is_a?(String)
      end
    end

    private

    def ssh_connection?
      port_available = false
      tries = 0

      while ! port_available && tries < 6
        %x{nc -z #{@host} #{@port}}
        port_available = $?.success?
        break if port_available
        print 'Waiting for ssh...' if tries < 1
        print '.'
        tries += 1
        sleep 4
      end

      puts ''
      port_available
    end
  end
end
