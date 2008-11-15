require 'thread'
require 'hotcocoa'
include HotCocoa
framework 'webkit'

# TODO:
# - stdin
# - do not perform_action if the code is not finished (needs a simple lexer)
# - split in multiple files

class Object
  # calls a method on the object on the main thread
  def send_on_main_thread(function_name, parameter = nil, asynchronous = true)
    function_name = function_name.to_s
    # if the target method has a parameter, we have to be sure the method name ends with a ':'
    function_name << ':' if parameter and not /:$/.match(function_name)
    performSelectorOnMainThread function_name, withObject: parameter, waitUntilDone: (not asynchronous)
  end
end

# EvalThread is the class that does all the code evaluation.
# The code is evaluated in a new thread mainly for 2 reasons:
# - so the application is not frozen if a commands takes too much time
# - to be able to find where to write the text for the standard output (using thread variables)
class EvalThread
  # Writer is the class to manage the standard output
  # The difficult part is to find the good target to print to,
  # especially if the user starts new threads
  # Warning: It won't work if the current thread is a NSThread or pure C thread
  #          but anyway NSThreads do no seem to work for the moment in MacRuby
  class Writer
    def self.set_stdout_target_for_thread(target)
      Thread.current[:_irb_stdout_target] = target
    end
    
    # a standard output object has only one mandatory method: write
    # it generally returns the number of characters written
    def write(str)
      find_target_and_call :write, str
    end
    
    # If puts is not there, Ruby will automaticall use the write method when using Kernel#puts,
    # but defining it has 2 advantages:
    # - if it is not defined, you cannot of course use $stdout.puts directly
    # - when Ruby emulates puts, it calls write twice
    #   (once for the string and once for the carriage return)
    #   but here we send the calls to another thread so being able
    #   to save up one (slow) interthread call is nice
    def puts(str)
      find_target_and_call :puts, str
      nil
    end
    
    private
    
    # The core of write/puts: tries to find the target where to
    # write the text and calls the indicated function on it
    # It returns the number of characters in the given string
    def find_target_and_call(function_name, str)
      current_thread = Thread.current
      target = current_thread[:_irb_stdout_target]
      
      # sends str to the target identified by the target local variable
      send_text = lambda do
        target.send_on_main_thread function_name, str
        str.length
      end
      
      # first, if we have a target in the thread, use it
      return send_text.call if target
      
      # if we do not have any target, search for a target in every thread in the ThreadGroup
      if group = current_thread.group
        group.list.each do |thread|
          return send_text.call if target = thread[:_irb_stdout_target]
        end
      end
      
      # if we do not find any target, just write it on STDERR
      STDERR.send(function_name, str)
    end
  end
  # replace Ruby's standard output
  $stdout = Writer.new
  
  def self.start(target)
    instance = EvalThread.new(target)
    Thread.new { instance.run }
    instance
  end

  def send_command(line_number, command)
    @queue_for_commands.push([line_number, command])
  end
  
  def end_thread
    @queue_for_commands.push([nil, :END])
  end

  def initialize(target)
    @target = target
    @queue_for_commands = Queue.new
    @binding = TOPLEVEL_BINDING.dup
  end
    
  def run
    # Create a new ThreadGroup and sets it as the group for the current thread
    # The ThreadGroup allows us to find the parent thread when the standard output is used
    # from a thread created by the user
    # (as new threads are automatically added to the ThreadGroup of the parent thread)
    ThreadGroup.new.add(Thread.current)
    
    Writer.set_stdout_target_for_thread(@target)
    loop do
      line_num, command = @queue_for_commands.pop
      break if command == :END

      eval_file = __FILE__
      eval_line = -1
      begin
        # eval_line must have exactly the line number where the eval call occurs
        eval_line = __LINE__; value = eval(command, @binding, 'macirb', line_num)
        back_from_eval "=> #{value.inspect}\n"
      rescue Exception => e
        backtrace = e.backtrace
        i = backtrace.index { |l| l.index("#{eval_file}:#{eval_line}") }
        if i == 0
          backtrace = []
        elsif i
          backtrace = backtrace[0..i-1]
        end
        back_from_eval "#{e.class.name}: #{e.message}\n" + (backtrace.empty? ? '' : "#{backtrace.join("\n")}\n")
      end
    end
  end
  
  private
  
  def back_from_eval(text)
    @target.send_on_main_thread :back_from_eval, text
  end
end

class Terminal
  # TODO this should not be needed in theory, since the window should forward the action to its subview  
  def on_copy(sender)
    @web_view.copy(sender)
  end
  
  def on_paste(sender)
    @web_view.paste(sender)
  end

  def base_html
    return <<-HTML
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
    <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <style type="text/css"><!--
        body, body * {
          font-family: Monaco;
          white-space: pre-wrap; /* in normal mode, WebKit sometimes adds nbsp when pressing space */
        }
      --></style>
    </head>
    <body></body>
    </html>
    HTML
  end
  
  def windowWillClose notification
    @window_closed = true
    @eval_thread.end_thread
  end
  
  def start
    @line_num = 0
    @history = [ ]
    @pos_in_history = 0
    
    @eval_thread = EvalThread.start(self)
    
    frame = [300, 300, 600, 400]
    w = NSApp.mainWindow
    if w
      frame[0] = w.frame.origin.x + 20
      frame[1] = w.frame.origin.y - 20
    end
    HotCocoa.window :frame => frame, :title => "MacIrb" do |win|
      @win = win
      @window_closed = false
      win.delegate = self
      win.contentView.margin = 0
      @web_view = web_view(:layout => {:expand => [:width, :height]})
      clear
      @web_view.editingDelegate = self
      @web_view.frameLoadDelegate = self
      win << @web_view
    end
  end
  
  def clear
    @web_view.mainFrame.loadHTMLString base_html, baseURL:nil
  end

  def webView view, didFinishLoadForFrame: frame
    # we must be sure the body is really empty because of the preservation of white spaces
    # we can easily have a carriage return left in the HTML
    document.body.innerHTML = ''
    write_prompt
  end
  
  def document
    @web_view.mainFrame.DOMDocument
  end
  
  def command_line
    document.getElementById('command_line')
  end
  
  def command_line_carret_to_beginning
    # move the carret of the command line to it first character
    cl = command_line
    range = document.createRange
    range.setStart cl, offset: 0
    range.setEnd cl, offset: 0
    @web_view.setSelectedDOMRange range, affinity: NSSelectionAffinityUpstream
  end
  
  def display_history
    command_line.innerText = @history[@pos_in_history] || ''
    # if we do not move the caret to the beginning,
    # we lose the focus if the command line is emptied
    command_line_carret_to_beginning
  end
  
  def webView webView, doCommandBySelector: command
    if command == 'insertNewline:' # Return
      perform_action
    elsif command == 'moveBackward:' # Alt+Up Arrow
      if @pos_in_history > 0
        @pos_in_history -= 1
        display_history
      end
    elsif command == 'moveForward:' # Alt+Down Arrow
      if @pos_in_history < @history.length
        @pos_in_history += 1
        display_history
      end
    # moveToBeginningOfParagraph and moveToEndOfParagraph are also sent by Alt+Up/Down
    # but we must ignore them because they move the cursor
    elsif command != 'moveToBeginningOfParagraph:' and command != 'moveToEndOfParagraph:'
      return false
    end
    true
  end

  def add_div(text)
    div = document.createElement('div')
    div.innerText = text
    write_element(div)
  end
  
  def write_element(element)
    document.body.appendChild(element)
  end
  
  def write(text)
    if @window_closed
      STDERR.write(text)
    else
      span = document.createElement('span')
      span.innerText = text
      write_element(span)
    end
  end
  
  def puts(text)
    # puts is just a write with a carriage return that returns nil
    write text
    write "\n"
  end

  def scroll_to_bottom
    body = document.body
    body.scrollTop = body.scrollHeight
    @web_view.setNeedsDisplay true
  end
  
  def end_edition
    if command_line
      command_line.setAttribute('contentEditable', value: nil)
      command_line.setAttribute('id', value: nil)
    end
  end

  def write_prompt
    end_edition

    table = document.createElement('table')
    row = table.insertRow(0)
    prompt = row.insertCell(-1)
    prompt.setAttribute('style', value: 'vertical-align: top;')
    prompt.innerText = '>>'
    typed_text = row.insertCell(-1)
    typed_text.setAttribute('contentEditable', value: 'true')
    typed_text.setAttribute('id', value: 'command_line')
    typed_text.setAttribute('style', value: 'width: 100%;')
    write_element(table)

    command_line.focus
    scroll_to_bottom
  end
  
  def perform_action
    @line_num += 1
    command = command_line.innerText
    if command.empty?
      write_prompt
      return
    end
    
    @history.push(command)
    @pos_in_history = @history.length

    @eval_thread.send_command(@line_num, command)
    end_edition
  end

  def back_from_eval(text)
    return if @window_closed
    write text
    write_prompt
  end
end

class Application

  def start
    application :name => "MacIrb" do |app|
      app.delegate = self
      start_terminal
    end
  end

  def on_new(sender)
    start_terminal
  end

  def on_close(sender)
    w = NSApp.mainWindow
    if w
      w.close
    else
      NSBeep()
    end
  end
  
  def on_clear(sender)
    NSApp.mainWindow.delegate.clear
  end

  private

  def start_terminal
    Terminal.new.start
  end
end

Application.new.start
