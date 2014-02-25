require 'getoptlong'
require 'pry'
require 'awesome_print'

module CliTool
  module OptionParser

    # Use to add the methods below to any class
    def self.included(base)
      base.extend(ClassMethods)
      base.options({
        debug: {
          argument: :none,
          documentation: [
            "This is used to trigger debug mode in your app. It will be set to #{base}.debug.",
            "In debug mode we do not respect the secure option and your secure fields will be displayed in clear text!",
            [:black, :white_bg]
          ]
        },
        help: {
          argument: :none,
          short: :'?',
          documentation: "Shows this help record."
        }
      })
    end

    module ClassMethods

      # Map for symbol types
      GOL_MAP = {
        none: GetoptLong::NO_ARGUMENT,
        optional: GetoptLong::OPTIONAL_ARGUMENT,
        required: GetoptLong::REQUIRED_ARGUMENT
      }

      # Create the options array
      def options(opts = nil)
        @@options ||= []

        # If no options were passed then return
        return @@options.uniq unless opts

        _create_preprocess_(opts)
        @@options = @@options.concat(_create_gola_(opts)).uniq
      end

      # Ensure the right format of the options (primarily dashes and casing)
      def optionify(option, retval = false)
        if option.is_a?(Array)
          optionify_all(option)
        else
          option = "#{option}".gsub(/^[\-]+/, '').gsub(/(-| )/, '_').to_sym

          # Help us get the primary option over the alias
          option =
            case retval
            when :set, :setter
              "#{option}="
            when :primary
              all_opts = __get_options(:all_options)

              if all_opts.has_key?(option)
                option
              else
                all_opts.map { |opt, option_args|
                  aliases = option_args[:aliases]
                  if aliases && aliases.include?(option)
                    opt
                  else
                    nil
                  end
                }.compact.flatten.first
              end
            else
              option
            end

          option.to_sym
        end
      end

      def optionify_all(option, retval = false)
        [option].compact.flatten.map { |x| optionify(x, retval) }
      end

      def trap!
        Signal.trap("INT") do |signo|
          if Signal.respond_to?(:signame)
            signal = Signal.signame(signo)
            puts "Received: #{signal}..."
            puts "Exiting..."
          else
            puts "#{signo} Exiting..."
          end
          exit 1
        end
      end

      # Handle running options
      def run(entrypoint = false, *args, &block)

        # Get the object to work with
        object =
          if args.last.class <= self
            args.pop
          elsif self < Singleton
            instance
          else
            new
          end

        # Get class variable hash
        class_vars = __get_options

        # Cache variables
        exit_code = 0
        max_puts_length = 0
        processed_options = []
        missing_arguments = []

        # Option setter proc
        option_setter = Proc.new do |option, value|
          option = optionify(option, :primary)
          processed_options << option

          # Help process values
          value =
            case value
            when ''
              true
            when 'true'
              true
            when 'false'
              false
            when 'nil', 'null'
              nil
            else
              value
            end

          # Run preprocessor on the data (if applicable)
          preprocessor = class_vars[:preprocessors][option]
          if preprocessor
            value = object.__send__(:instance_exec, value, &preprocessor)
          end

          # Show notice of the setting being set on the instance
          if class_vars[:private_options].include?(option) && ! instance.debug
            m = "Setting @#{option} = #{'*' * value.length} :: Value hidden for privacy"
            max_puts_length = m.length if m.length > max_puts_length
            puts m, :blue
          else
            m = "Setting @#{option} = #{value}"
            max_puts_length = m.length if m.length > max_puts_length
            puts m, :green
          end

          # Do the actual set for us
          object.__send__(optionify(option, :set), value)
        end

        # Actually grab the options from GetoptLong and process them
        puts "\nCliTool... Loading Options...\n", :blue
        puts '#' * 29, [:red_bg, :red]
        class_vars[:default_options].to_a.each(&option_setter)
        begin
          GetoptLong.new(*options).each(&option_setter)
        rescue GetoptLong::MissingArgument => e
          missing_arguments << e.message
        end
        puts '#' * 29, [:red_bg, :red]
        puts ''

        # If we wanted help in the first place then don't do any option dependency validations
        unless object.help

          # Handle any missing arguments that are required!
          unless missing_arguments.empty?
            missing_arguments.each { |m| puts "The required #{m}", :red }
            puts ''

            object.help = true
            exit_code   = 1
          end

          # Get the missing options that were expected
          missing_options = class_vars[:required_options].keys - processed_options

          # Handle missing options and their potential alternatives
          __slice_hash(class_vars[:required_options], *missing_options).each do |option, option_args|
            if (option_args[:alternatives] & processed_options).empty?
              object.help = true
              exit_code   = 1
            else
              missing_options.delete(option)
            end
          end

          # Ensure that the dependencies for options are met (if applicable)
          __slice_hash(class_vars[:required_options], *processed_options).each do |option, option_args|
            missing_dependencies = option_args[:dependencies] - processed_options
            missing_dependencies.each do |dep_opt|
              puts "The option `--#{option}' expected a value for `--#{dep_opt}', but not was received", :red
              missing_options << dep_opt

              object.help = true
              exit_code   = 1
            end

            puts '' unless missing_dependencies.empty?
          end

          # Raise an error when required options were not provided.
          # Change the exit code and enable help output (which will exit 1; on missing opts)
          unless missing_options.empty?
            missing_options.uniq.each do |option|
              puts "The required option `--#{option}' was not provided.", :red
            end

            object.help = true
            exit_code   = 1
          end
        end

        # Show the help text
        if object.help || exit_code == 1
          puts help(nil, missing_options || [])
          exit(exit_code || 0)
        end

        # Handle the entrypoint
        if entrypoint
          entrypoint = optionify(entrypoint)
          object.__send__(entrypoint, *args, &block)
        else
          object
        end
      end

      def help(message = nil, missing_options = [])
        if message.nil?
          help_text = __get_options(:all_options).map do |option, option_args|

            # Show the argument with the default value (if applicable)
            case option_args[:argument]
            when :required
              long_dep = "=<#{option_args[:default] || 'value'}>"
              short_dep = " <#{option_args[:default] || 'value'}>"
            when :optional
              long_dep = "=[#{option_args[:default] || 'value'}]"
              short_dep = " [#{option_args[:default] || 'value'}]"
            when :none
              long_dep = ''
              short_dep = ''
            end

            # Set up the options list
            message = "\t" + (option_args[:aliases] << option).map{ |x| "--#{x}#{long_dep}"}.join(', ')
            message << ", -#{option_args[:short]}#{short_dep}" if option_args[:short]
            message << %{ :: Default: "#{option_args[:default]}"} if option_args[:default]

            # Highlight missing options
            unless missing_options.empty?
              missing_required_option = ! (missing_options & option_args[:aliases]).empty?
              message = colorize(message, missing_required_option ? :red : :default)
            end

            # Prepare the option documentation
            if option_args[:documentation]
              doc = option_args[:documentation]
              if doc.is_a?(Array) \
                 && (doc.last.is_a?(Symbol) \
                 || (doc.last.is_a?(Array) \
                     && doc.last.reduce(true) { |o, d| o && d.is_a?(Symbol) }
                 ))

                colors = doc.pop
                len = doc.reduce(0) { |o, s| s.length > o ? s.length : o }
                doc = doc.map{ |s| colorize(s.ljust(len, ' '), colors) }.join("\n\t\t")
              elsif doc.is_a?(Array)
                doc = doc.join("\n\t\t")
              end

              message << %{\n\t\t#{doc}}
              message << "\n"
            end
          end

          # Print and format the message
          %{\nHelp: #{$0}\n\n### Options ###\n\n#{help_text.join("\n")}\n### Additional Details ###\n\n#{@@help_message || "No additional documentation"}\n}
        else
          @@help_message = message.split(/\n/).map{ |x| "\t#{x.strip}" }.join("\n")
        end
      end

      private

      def _create_preprocess_(opts)

        # Set the preprocessor for options (used primarily for formatting or changing types)
        __generic_option_reducer(:preprocessors, {}, opts, only_with: :preprocess) do |pre_proc, (options, option_args)|
          pre_proc.merge(options.shift => option_args[:preprocess])
        end

        # Set the required options and dependencies for the parser
        __generic_option_reducer(:required_options, {}, opts, only_with: :required) do |req_opts, (options, option_args)|
          primary_name = options.shift

          # Set the aliases for the required option
          hash = (option_args[:required].is_a?(Hash) ? option_args[:required] : {}).merge(aliases: options)

          # Ensure that the option names are properly formatted in the alternatives and dependencies
          hash[:dependencies] = optionify_all(hash[:dependencies])
          hash[:alternatives] = optionify_all(hash[:alternatives])

          # Merge together the options as required
          if option_args[:required].is_a?(Hash)
            req_opts.merge(primary_name => hash)
          else
            req_opts.merge(primary_name => hash.merge(force: !! option_args[:required]))
          end
        end

        # Create a cache of all the options available
        __generic_option_reducer(:all_options, {}, opts) do |opt_cache, (options, option_args)|
          primary_name = options.shift

          if option_args.is_a?(Hash)
            opt_cache.merge(primary_name => option_args.merge(aliases: options))
          else
            opt_cache.merge(primary_name => {aliases: options, argument: option_args})
          end
        end

        # Create a list of the "secure options" (hide value from client; as much as possible)
        __generic_option_reducer(:private_options, [], opts, only_with: :private) do |priv_opts, (options, option_args)|
          primary_name = options.shift

          if option_args[:private]
            priv_opts << primary_name
          else
            priv_opts
          end
        end

        # Set the default options to be set when no values are passed
        __generic_option_reducer(:default_options, {}, opts, only_with: :default) do |default_opts, (options, option_args)|
          default_opts.merge(options.shift => option_args[:default])
        end

        # Create the attribute accessors
        opts.keys.each do |options|
          options = optionify_all(options)
          primary_name = options.shift
          attr_accessor(primary_name)
        end
      end

      def _create_gola_(opts)
        gola = []

        # Loop through the options to create
        # the GetoptLong configuration array
        opts.each do |opt, details|

          short = nil
          dependency = :none

          # If we have extended details determine them
          if details.is_a?(Hash)
            short = details[:short]
            dependency = details[:argument]
          else
            dependency = details
          end

          # Prepare the GetoptLong Array option
          golao  = []
          golao << "-#{short}" if short
          golao << GOL_MAP[dependency.to_sym]

          # If the option has aliases then create
          # additional GetoptLong Array options
          if opt.is_a?(Array)
            opt.each_with_index do |key, i|
              golaot = golao.dup
              golaot.shift if i > 0 # Remove Short Code
              golaot.unshift("--#{key}")
              gola << golaot
            end
          else
            golao.unshift("--#{opt}")
            gola << golao
          end
        end

        gola
      end

      private

      def __generic_option_reducer(instance_var, default = [], opts = {}, args = {}, &block)
        opts = opts.reduce({}) { |o, (k, v)| o.merge(optionify_all(k) => v) }

        # Require certain keys be in the option cache. This is done to save time of the processing and make it easier to write
        # the code to parse the options and set the requirements and dependencies of each option.
        if args[:only_with]
          opts = opts.select { |k, v| v.is_a?(Hash) && [args[:only_with]].flatten.reduce(true) { |o, key| o && v.has_key?(key) } }
        end

        # Run the reducer and set the class variables accordingly
        class_variable_set("@@__#{instance_var}", default) unless class_variable_defined?("@@__#{instance_var}")
        class_variable_set("@@__#{instance_var}", opts.reduce(class_variable_get("@@__#{instance_var}") || default, &block))
      end

      def __get_options(instance_var = nil)
        instance_var ? class_variable_get("@@__#{instance_var}") : Proc.new {
          self.class_variables.reduce({}) do |o, x|
            o.merge(x[4..-1].to_sym => class_variable_get(x))
          end
        }.call
      end

      def __slice_hash(hash, *keys)
        keys.reduce({}) do |out, key|
          hash.has_key?(key) ? out.merge(key => hash[key]) : out
        end
      end
    end
  end
end
