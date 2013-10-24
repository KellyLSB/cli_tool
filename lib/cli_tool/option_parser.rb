require 'getoptlong'

module CliTool
  module OptionParser

    # Use to add the methods below to any class
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods

      # Map for symbol types
      GOL_MAP = {
        :none     => GetoptLong::NO_ARGUMENT,
        :optional => GetoptLong::OPTIONAL_ARGUMENT,
        :required => GetoptLong::REQUIRED_ARGUMENT
      }

      # Create the options array
      def options(opts = nil)
        @@options ||= []

        # If no options were passed then return
        return @@options.uniq unless opts

        _create_attrs_(opts)
        default_options(opts)
        @@options = @@options.concat(_create_gola_(opts)).uniq
      end

      def default_options(opts = {})
        @@defaults ||= []

        # If no options were passed then return
        return @@defaults.uniq.inject({}) { |o,(k,v)| o[k] = v; o } unless opts

        # Set the default options
        opts.each do |opt, details|
          next unless details.is_a?(Hash)
          next unless details[:default]
          opt = opt.first if opt.is_a?(Array)
          @@defaults << [optionify(opt), details[:default]]
        end

        @@defaults = @@defaults.uniq
      end

      # Parse to correct option set
      def optionify(option, setter = false)
        option = "#{option}".gsub(/^[\-]+/, '').gsub(/(-| )/, '_')
        (setter ? option + '=' : option).to_sym
      end

      # Handle running options
      def run(entrypoint = false, *args)
        if args.last.instance_of?(self)
          instance = args.pop
        else
          instance = new
        end

        # Option Setter Proc
        option_setter = Proc.new do |option, value|
          value = case value
          when ''
            true
          when 'true'
            true
          when 'false'
            false
          else
            value
          end

          puts "Setting @#{optionify(option)} = #{value}"
          instance.__send__(optionify(option, :set), value)
        end

        # Set options
        puts "CliTool... Loading Options..."
        default_options.each(&option_setter)
        GetoptLong.new(*options).each(&option_setter)
        puts ''

        # Handle the entrypoint
        if entrypoint
          entrypoint = optionify(entrypoint)
          instance.__send__(entrypoint, *args)
        else
          instance
        end
      end

      private

      def _create_attrs_(opts)

        # Get the option keys for attr creation
        keys = opts.keys

        # "symlink" the additional names to the original method
        keys.each do |key|
          default = nil
          key = [key] unless key.is_a?(Array)
          key.each_with_index do |k, i|
            if i < 1
              default = optionify(k)
              attr_accessor(default)
            else
              define_method(optionify(k, :set), Proc.new { |x| send("#{default}=", x) })
            end
          end
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
            dependency = details[:dependency]
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
            opt.each do |key|
              golaot = golao.dup
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
    end
  end
end
