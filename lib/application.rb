require 'hotcocoa'
framework 'webkit'

# TODO:
# - stdin
# - copy/paste (with the app menu)
# - html display
# - do not perform_action if the code is not finished (needs a simple lexer)
class Application
  include HotCocoa

  class Writer
    def initialize(target)
      @target = target
    end
    def write(str)
      @target.write_text(str)
      str.length
    end
    def puts(str)
      write str
      write "\n"
      nil
    end
  end
  
  def load_html_generator
    Dir.glob(NSBundle.mainBundle.resourcePath.fileSystemRepresentation+"/lib/generator/*.rb").each do |filename|
      load filename
    end
  end
    
  def start
    @line_num = 0
    @history = [ ]
    @pos_in_history = 0
    @binding = TOPLEVEL_BINDING
    
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
    
    #load_html_generator # can't use it for the moment because of MacRuby bugs
    application :name => "MacIrb" do |app|
      app.delegate = self

      window :frame => [100, 100, 900, 500], :title => "MacIrb" do |win|
        @win = win
        win.will_close { exit }
        win.contentView.margin = 0
        @web_view = web_view(:layout => {:expand => [:width, :height]})
        @web_view.mainFrame.loadHTMLString base_html, baseURL:nil
        @web_view.editingDelegate = self
        @web_view.frameLoadDelegate = self
        win << @web_view
      end
    end
  end
  
  def webView view, didFinishLoadForFrame: frame
    writer = Writer.new(self)
    $stdout = writer
    # we must be sure the body is really empty because of the preservation of white spaces
    # we can easily have a carriage return left in the HTML
    document.body.innerHTML = ''
    #$stderr = writer # for debugging it may be better to disable this (and look in Console.app)
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

  def add_div(text, is_html=false)
    div = document.createElement('div')
    if is_html
      div.innerHTML = text
    else
      div.innerText = text
    end
    write_element(div)
  end
  
  def write_element(element)
    document.body.appendChild(element)
  end
  
  def write_text(text)
    span = document.createElement('span')
    span.innerText = text
    write_element(span)
  end

  def scroll_to_bottom
    body = document.body
    body.scrollTop = body.scrollHeight
    @web_view.setNeedsDisplay true
  end

  def write_prompt
    if command_line
      command_line.setAttribute('contentEditable', value: nil)
      command_line.setAttribute('id', value: nil)
    end

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

    eval_file = __FILE__
    eval_line = -1
    begin
      # eval_line must have exactly the line number where the eval call occurs
      eval_line = __LINE__; value = eval(command, @binding, 'macirb', @line_num)
      #add_div(value.html_representation, true) # can't use it for the moment because of MacRuby bugs
      add_div(value.inspect)
    rescue Exception => e
      backtrace = e.backtrace
      i = backtrace.index { |l| l.index("#{eval_file}:#{eval_line}") }
      if i == 0
        backtrace = []
      elsif i
        backtrace = backtrace[0..i-1]
      end
      add_div("#{e.class.name}: #{e.message}" + (backtrace.empty? ? '' : "\n#{backtrace.join("\n")}"))
    end
    write_prompt
  end
  
  # file/open
  def on_open(menu)
  end
  
  # file/new 
  def on_new(menu)
  end
  
  # help menu item
  def on_help(menu)
  end
  
  # This is commented out, so the minimize menu item is disabled
  #def on_minimize(menu)
  #end
  
  # window/zoom
  def on_zoom(menu)
  end
  
  # window/bring_all_to_front
  def on_bring_all_to_front(menu)
  end
end

Application.new.start
