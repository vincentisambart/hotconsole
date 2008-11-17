require 'lib/eval_thread' # for EvalThread and standard output redirection

require 'hotcocoa'
framework 'webkit'
include HotCocoa

# TODO:
# - stdin
# - do not perform_action if the code typed is not finished (needs a simple lexer)
# - when closing the application, if code is running, ask for what to do (cancel, kill and close all)
# - add an help message in the windows when they are opened

class Terminal
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
  
  def alertDidEnd alert, returnCode: return_code, contextInfo: context_info
    return if return_code == NSAlertSecondButtonReturn # do nothing if the use presses cancel
    
    # in all cases, first ask the thread to end nicely if possible
    @eval_thread.end_thread
    
    @window.close
    @window_closed = true
    
    @eval_thread.kill_running_threads if return_code == NSAlertFirstButtonReturn # kill the running code if asked
  end
  method_signature "alertDidEnd:returnCode:contextInfo:", "v@:@i^v" # MacRuby needs it not to crash
  
  def windowShouldClose win
    return true if command_line and not @eval_thread.children_threads_running?
    alert = NSAlert.alloc.init
    alert.messageText = "Some code is still running in this console.\nDo you really want to close it?"
    alert.alertStyle = NSCriticalAlertStyle
    alert.addButtonWithTitle("Close and kill")
    alert.addButtonWithTitle("Cancel")
    alert.addButtonWithTitle("Close and let run")
    alert.beginSheetModalForWindow @window, modalDelegate: self, didEndSelector: "alertDidEnd:returnCode:contextInfo:", contextInfo: nil
    false
  end
  
  def start
    @line_num = 1
    @history = [ ]
    @pos_in_history = 0
    
    @eval_thread = EvalThread.new(self)
    
    frame = [300, 300, 600, 400]
    w = NSApp.mainWindow
    if w
      frame[0] = w.frame.origin.x + 20
      frame[1] = w.frame.origin.y - 20
    end
    window :frame => frame, :title => "HotConsole" do |win|
      @window = win
      @window_closed = false
      @window.delegate = self # for windowShouldClose
      @window.contentView.margin = 0
      @web_view = web_view(:layout => {:expand => [:width, :height]})
      clear
      @web_view.editingDelegate = self # for webView:doCommandBySelector:
      @web_view.frameLoadDelegate = self # for webView:didFinishLoadForFrame:
      @window << @web_view
    end
  end
  
  def clear
    if command_line
      @next_prompt_command = command_line.innerText
    else
      @next_prompt_command = nil
    end
    @web_view.mainFrame.loadHTMLString base_html, baseURL:nil
  end

  def webView view, didFinishLoadForFrame: frame
    # we must be sure the body is really empty because of the preservation of white spaces
    # we can easily have a carriage return left in the HTML
    document.body.innerHTML = ''
    write_prompt
  end
  
  # return the HTML document of the main frame
  def document
    @web_view.mainFrame.DOMDocument
  end
  
  # returns the DOM node for the command line
  # (or nil if there is no command line currently)
  def command_line
    document.getElementById('command_line')
  end
  
  # move the carret of the command line to its first character
  def command_line_carret_to_beginning
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
  
  # callback called when a command by selector is run on the WebView
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

  # simply writes (appends) a DOM element to the WebView
  def write_element(element)
    document.body.appendChild(element)
  end
  
  def write(text)
    if @window_closed
      # if the window was closed while code that printed text was still running,
      # the text is displayed on the standard error output
      STDERR.write(text)
    else
      # if the window is still opened, just put the text
      # in a DOM span element and writes it on the WebView
      span = document.createElement('span')
      span.innerText = text
      write_element(span)
    end
  end
  
  # puts is just a write of the text followed by a carriage return and that returns nil
  def puts(text)
    # we do not call just write("#{text}\n") because of encoding problems
    # and bugs in string concatenation
    # note also that Ruby itself also does it in two calls to write
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
    if @next_prompt_command
      typed_text.innerText = @next_prompt_command
      @next_prompt_command = nil
    end
    write_element(table)

    command_line.focus
    scroll_to_bottom
  end
  
  # executes the code written on the prompt when the user validates it with return
  def perform_action
    current_line_number = @line_num
    command = command_line.innerText
    @line_num += command.count("\n")+1
    if command.strip.empty?
      write_prompt
      return
    end
    
    @history.push(command)
    @pos_in_history = @history.length

    # the code is sent to an other thread that will do the evaluation
    @eval_thread.send_command(current_line_number, command)
    # the user must not be able to modify the prompt until the command ends
    # (when back_from_eval is called)
    end_edition
  end

  # back_from_eval is called when the evaluation thread has finished its evaluation of the given code
  # text is either the representation of the value returned by the code executed, or the backtrace of an exception
  def back_from_eval(text)
    # if the window was closed while code was still executing,
    # we can just ignore the call because there is no need
    # to print the result and a new prompt
    return if @window_closed
    write text
    write_prompt
  end
end

class Application
  def start
    application :name => "HotConsole" do |app|
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
      w.performClose self
    else
      NSBeep()
    end
  end
  
  def on_clear(sender)
    w = NSApp.mainWindow
    if w
      terminal = w.delegate
      # the user can't clear the window
      # if some code is still executing
      if terminal.command_line
        terminal.clear
      else
        NSBeep()
      end
    else
      NSBeep()
    end
  end

  private

  def start_terminal
    Terminal.new.start
  end
end

Application.new.start
