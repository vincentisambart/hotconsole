require 'lib/eval_thread' # for EvalThread and standard output redirection

require 'hotcocoa'
include HotCocoa
framework 'webkit'

# TODO:
# - stdin
# - do not perform_action if the code is not finished (needs a simple lexer)

class Terminal
  # TODO this should not be needed in theory, since the window should forward the action to its subview  
  def on_copy(sender)
    @web_view.copy(sender)
  end
  
  def on_paste(sender)
    @web_view.paste(sender)
  end

  def on_cut(sender)
    @web_view.cut(sender)
  end

  def on_undo(sender)
    @web_view.undoManager.undo
  end

  def on_redo(sender)
    @web_view.undoManager.redo
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
  
  # when the window is closes, we want the evaluating thread to die
  # (after ending its current evaluation if it is still evaluating code)
  def windowWillClose notification
    @window_closed = true
    @eval_thread.end_thread
  end
  
  def start
    @line_num = 1
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
      @win.delegate = self # for the diverse on_XXXX and windowWillClose
      @win.contentView.margin = 0
      @web_view = web_view(:layout => {:expand => [:width, :height]})
      clear
      @web_view.editingDelegate = self # for webView:doCommandBySelector:
      @web_view.frameLoadDelegate = self # for webView:didFinishLoadForFrame:
      @win << @web_view
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
