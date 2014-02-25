require 'io/console'
require 'timeout'

module CliTool
  module StdinOut
    class MissingInput < StandardError; end;

    ANSI_COLORS = {
      reset: 0,
      bold: 1,
      italic: 3,
      underline: 4,
      inverse: 7,
      strike: 9,
      bold_off: 22,
      italic_off: 23,
      underline_off: 24,
      inverse_off: 27,
      strike_off: 29,
      black: 30,
      red: 31,
      green: 32,
      yellow: 33,
      blue: 34,
      magenta: 35,
      purple: 35,
      cyan: 36,
      white: 37,
      default: 39,
      black_bg: 40,
      red_bg: 41,
      green_bg: 42,
      yellow_bg: 43,
      blue_bg: 44,
      magenta_bg: 45,
      purple_bg: 45,
      cyan_bg: 46,
      white_bg: 47,
      default_bg: 49
    }

    def self.included(base)
      base.extend(ClassMethods)
      base.__send__(:include, ClassMethods)
    end

    module ClassMethods

      # Handle putsing of information (supports color and sleeps)
      def puts(text, color = :reset, timer = nil)

        # Process information for ANSI color codes
        super(colorize(text, color))

        # Sleep after displaying the message
        if timer
          puts(colorize("Sleeping for #{timer} seconds...", color))
          sleep(timer)
        end
      end

      def print(text, color = :reset, timer = nil)

        # Process information for ANSI color codes
        super(colorize(text, color))

        # Sleep after displaying the message
        if timer
          puts(colorize("Sleeping for #{timer} seconds...", color))
          sleep(timer)
        end
      end

      def input(message = '', color = :reset, timer = nil, default = nil)

        # Prompt for input
        print("#{message} ", color)

        # Get the input from the CLI
        if block_given? && yield == :noecho
          gets = Proc.new do
            STDIN.noecho(&:gets).strip
            print "\n"
          end
        else
          gets = Proc.new do
            STDIN.gets.strip
          end
        end

        # Handle timing out
        result = begin
          if timer
            Timeout::timeout(timer, &gets)
          else
            gets.call
          end
        rescue Timeout::Error # Verify that this is correct?
          default
        end

        result
      end

      def password(*a)
        input(*a) { :noecho }
      end

      def confirm(message, color = :reset, default = :n, timer = nil)

        # Handle the default value
        default = "#{default}".downcase[0..0].to_sym

        # Get the prompt
        prompt = if default == :y
           'Y/n'
        else
          'y/N'
        end

        begin
          # Prompt for answer
          result = input("#{message} [#{prompt}]", color, timer).strip
          result = result.empty? ? default : result.downcase[0..0].to_sym
          raise MissingInput unless [:y, :n].include?(result)
        rescue MissingInput
          puts "Sorry that input was not accepted", :red
          retry
        end

        result
      end

      def colorize(text, *color)

        # Determine what to colors we should use
        color = [:reset] if color.empty?
        color = color.flatten

        # Prepare the colorizing prefix for the text
        prefix = color.inject('') do |o, c|
          ANSI_COLORS[c] ? o << "\e[#{ANSI_COLORS[c]}m" : o
        end

        "#{prefix}#{text}\e[0m" # Add color
      end
    end
  end
end
