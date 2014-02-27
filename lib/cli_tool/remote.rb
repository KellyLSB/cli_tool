require 'singleton'
require 'awesome_print'
require 'pry'

module CliTool
  module Remote
    class WaitingForSSH < StandardError; end;
    class Failure < StandardError; end;

    class Script
      include CliTool::StdinOut
      attr_accessor :commands
      attr_accessor :environment
      attr_accessor :indent

      def initialize
        @environment = {}
        @commands    = []
        @apt         = {}
        @remote_installed = 0
        @indent      = 0
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
        @environment['DEBIAN_FRONTEND'] = %{noninteractive}
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
        packages.each do |package|
          @remote_installed += 1
          num = "#{@remote_installed}".rjust(3,'0')
          tmp = "/tmp/package#{num}.deb"
          curl(package, tmp, :sudo)
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

      def file_exist?(file, exist = true, &block)
        if?((exist ? '' : '! ') + %{-f "#{file}"}, &block)
      end

      def directory_exist(directory, exist = true, &block)
        if?((exist ? '' : '! ') + %{-d "#{file}"}, &block)
      end

      ##########
      #= Exec =#
      ##########

      def exec(script, sudo = false, sudouser = :root)
        if File.exist?(script)
          script = File.read(script)
        end

        # Remove unnecessary indentation
        if script.include?("\n")
          script  = script.split("\n").reject { |x| x.strip.empty? }
          indents = script.first.match(/^([\t ]*)(.*)$/)[1]
          script  = script.map { |x| x.gsub(/#{indents}/, '') }.join("\n")
        end

        # Wrap the script in a sudoers block
        if sudo || sudo == :sudo
          sudo_script  = %{sudo su -c "/bin/bash" #{sudouser || :root}}
          sudo_script << %{ <<-EOF\n#{get_environment_exports}#{script.rstrip}\nEOF}
          script = sudo_script
        end

        @commands << script.rstrip.gsub('$', '\$')
        self
      end

      def to_s(indent = 0)
        @commands.reduce([get_environment_exports(@indent)]){ |out, x|  out << ((' ' * @indent) + x) }.join("\n")
      end

      private

      def apt(command, *p, &b)
        @environment['DEBIAN_FRONTEND'] = %{noninteractive}
        return aptkey(*p, &b) if command == :key
        #return if ((@apt[command] ||= []) - p).empty? && [:install, :purge, :remove].include?(command)
        #((@apt[command] ||= []) << p).flatten!
        exec(("apt-get -o Dpkg::Options::='--force-confnew' -q -y --force-yes #{command} " + p.map(&:to_s).join(' ')), :sudo)
        self
      end

      def check_installed(installed, *p, &block)
        installed = installed ? '1' : '0'

        condition = packages.reduce([]) { |command, package|
          command << %{[ "$(dpkg -s #{package} > /dev/null 2>1 && echo '1' || echo '0')" == '#{installed}' ]}
        }.join(' && ')

        if?(condition, &block)
        self
      end

      def if?(condition, &block)
        exec(%{if [ #{condition} ]; then\n"} << Script.new.__send__(:instance_exec, &block).to_s(@indent + 2) << "\nfi")
        self
      end

      def get_environment_exports(indent = 0)
        @environment.reduce([]) { |out, (key, val)|
          out << %{export #{(' ' * indent)}#{key.upcase}=#{val}}
        }.join("\n") << "\n"
      end
    end

    def self.included(base)
      base.__send__(:include, ::Singleton)
      base.__send__(:include, ::CliTool::StdinOut)
      base.__send__(:include, ::CliTool::OptionParser)
      base.__send__(:include, ::CliTool::SoftwareDependencies)
      base.extend(ClassMethods)
      base.software(:ssh, :nc)
      base.options({
        [:username, :user] => {
          default: %x{whoami}.strip,
          argument: :required,
          short: :u,
          documentation: 'SSH username'
        },
        [:password, :pass] => {
          argument: :required,
          short: :p,
          documentation: 'SSH password (not implemented)',
          private: true
        },
        identity: {
          argument: :required,
          short: :i,
          documentation: 'SSH key to use'
        },
        host: {
          argument: :required,
          short: :h,
          documentation: 'SSH host to connect to',
          require: true
        },
        port: {
          default: '22',
          argument: :required,
          documentation: 'SSH port to connect on'
        },
        [:tags, :tag] => {
          argument: :required,
          short: :t,
          documentation: 'Run tags (limit scripts to run)',
          preprocess: ->(tags) { tags.split(',').map{ |x| x.strip.to_sym } }
        }
      })
    end

    module ClassMethods
      def script_plugin(object)
        Script.__send__(:include, object)
      end

      def script(options = {}, &block)
        script = Proc.new do
          run = true

          # Allow restricting the runs based on the tags provided
          if self.tags
            script_tags = (options[:tags] || []).concat([options[:tag]]).compact.flatten
            run = false if (self.tags & script_tags).empty?
          end

          # Run only when the tag is provided if tag_only option is provided
          run = false if run && options[:tag_only] == true && self.tags.empty?

          if run # Do we want to run this script?
            build_script = Script.new
            build_script.__send__(:instance_exec, self, &block)
            if options[:reboot] == true
              build_script.exec('shutdown -r now', :sudo)
              puts "\nServer will reboot upon completion of this block!\n", [:blue, :italic]
            elsif options[:shutdown] == true
              build_script.exec('shutdown -h now', :sudo)
              puts "\nServer will shutdown upon completion of this block!\n", [:blue, :italic]
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

      def run_suite!(*a, &b)
        run(:run_suite!, *a, &b)
      end

      def run!(command, *a, &b)
        run(command, *a, &b)
      end

      def custom!(*a, &b)
        Proc.new { |obj| obj.instance_exec(*a, &b) }
        false
      end

      private

      def queue(*items)
        return @@queue || [] if items.empty?
        items.map!{ |x| x.is_a?(Script) ? x.to_s : x }.flatten!
        ((@@queue ||= []) << items).flatten!
        self
      end
    end

    def export(dir = nil)
      self.class.queue.select{ |x| x.is_a?(String) }
    end

    def remote_exec!(script)
      ssh_cmd =[ 'ssh -t -t' ]
      ssh_cmd << "-i #{@identity}" if @identity
      ssh_cmd << "-p #{@port}"     if @port
      ssh_cmd << "#{@username}@#{@host}"
      ssh_cmd << "/bin/bash -s"

      # Show debug script
      if self.debug
        pretty_cmd = ssh_cmd.concat(["<<-SCRIPT\n#{script}\nexit;\nSCRIPT"]).join(' ')
        message = "About to run remote process over ssh on #{@username}@#{@host}:#{@port}"
        puts message, :blue
        puts '#' * message.length, :blue
        puts pretty_cmd, :green
        puts '#' * message.length, :blue
        confirm "Should we continue?", :orange
      else
        sleep 2
      end

      #ssh_cmd << %{"#{script.gsub(/"/, '\\\1')}"}
      ssh_cmd << "<<-SCRIPT\n#{script}\nexit;\nSCRIPT"
      ssh_cmd << %{| grep -v 'stdin: is not a tty'}

      puts "Running Script", [:blue, :italic]

      # Run command if a connection is available
      return false unless ssh_connection?
      puts "" # Empty Line
      system(ssh_cmd.join(' '))
      exec_success = $?.success?
      puts "" # Empty Line

      # Print message with status
      if exec_success
        puts "Script finished successfully.", [:green, :italic]
      else
        puts "There was an error running remote execution!", [:red, :italic]
      end

      # Return status
      exec_success
    end

    def run_suite!
      self.class.__send__(:queue).each do |item|
        item = instance_exec(self, &item) if item.is_a?(Proc)
        remote_exec!(item.to_s) if item.is_a?(String) || item.is_a?(Script)
      end
    end

    def tag?(*tgs)
      self.tags && ! (self.tags & tgs).empty?
    end

    private

    def ssh_connection?
      port_available = false
      tries = 0

      while ! port_available && tries < 6
        %x{nc -z #{@host} #{@port}}
        port_available = $?.success?
        break if port_available
        print 'Waiting for ssh...', [:blue, :italic] if tries < 1
        print '.'
        tries += 1
        sleep 4
      end

      puts ''
      port_available
    end
  end
end
