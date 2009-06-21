require 'thread' # for Queue
require 'lib/helpers' # for Object#send_on_main_thread

# EvalThread is the class that does all the code evaluation.
# The code is evaluated in a new thread mainly for 2 reasons:
# - so the application is not frozen if a commands takes too much time
# - to be able to find where to write the text for the standard output (using thread variables)
class EvalThread
  # Writer is the class to manage the standard output.
  # The difficult part is to find the good target to print to,
  # especially if the user starts new threads
  # warning: It won't work if the current thread is a NSThread or pure C thread,
  #          but anyway for the moment NSThreads do no seem to work well in MacRuby
  class Writer
    # sets the target where to write when something is written on the standard output
    def self.set_stdout_target_for_thread(target)
      Thread.current[:_irb_stdout_target] = target
    end
    
    # a standard output object has only one mandatory method: write.
    # it generally returns the number of characters written
    def write(obj)
      if obj.respond_to?(:to_str)
        str = obj
      else
        str = obj.to_s
      end
      find_target_and_call :write, str
      str.length
    end
    
    # if puts is not there, Ruby will automatically use the write
    # method when calling Kernel#puts, but defining it has 2 advantages:
    # - if puts is not defined, you cannot of course use $stdout.puts directly
    # - when Ruby emulates puts, it calls write twice
    #   (once for the string and once for the carriage return)
    #   but here we send the calls to another thread so it's nice
    #   to be able to save up one (slow) interthread call
    def puts(*args)
      find_target_and_call :puts, args
      nil
    end
    
    private
    
    # the core of write/puts: tries to find the target where to
    # write the text and calls the indicated function on it.
    # it returns the number of characters in the given string
    def find_target_and_call(function_name, obj)
      target = $current_stdout_target
      
      # first, if we have a target in the thread, use it
      return target.send(function_name, obj) if target
      
      # if we still do not have any target, try to get the most recently used and opened terminal
      target = $terminals.last
      return target.send(function_name, obj) if target
      
      # if we do not find any target, just write it on STDERR
      STDERR.send(function_name, obj)
    end
  end
  $current_stdout_target = nil
  # replace Ruby's standard output
  $stdout = Writer.new
  
  # sends a command to evaluate.
  # the line_number is not computed internally because the empty lines
  # are not sent to the eval thread but still increase the line number
  def send_command(line_num, command)
    $current_stdout_target = @target  
    # eval_file and eval_line are used to clean up the backtrace of catched exceptions
    eval_file = __FILE__
    eval_line = -1
    begin
      # eval_line must have exactly the line number where the eval call occurs
      eval_line = __LINE__; value = eval(command, @binding, 'hotconsole', line_num)
      #@underscore_assigner.call(value)
      @target.back_from_eval "=> #{value.inspect}\n"
    rescue Exception => e
      backtrace = e.backtrace
      # we try to remove the backtrace of the call to eval itself
      # because it only confuses the user
      i = backtrace.index { |l| l.index("#{eval_file}:#{eval_line}") }
      if i == 0
        backtrace = []
      elsif i
        backtrace = backtrace[0..i-1]
      end
      @target.back_from_eval "#{e.class.name}: #{e.message}\n" + (backtrace.empty? ? '' : "#{backtrace.join("\n")}\n")
    end
  end
  
  def end_thread
  end
  
  # kill the evaluation thread and its children
  def kill_running_threads
  end
  
  def children_threads_running?
    false
  end
  
  def initialize(target)
    @target = target
    @binding = TOPLEVEL_BINDING.dup
    #@underscore_assigner = eval("_ = nil; proc { |val| _ = val }", @binding)
  end
end
