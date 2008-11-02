require 'hotcocoa'
framework 'webkit'

# TODO:
# - stdin
# - wrap too long text
# - history (up/down or maybe alt+up/alt+down)
# - copy/paste
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
    
  def start
    @line_num = 0
    @binding = TOPLEVEL_BINDING
    
    def base_html
      return <<-HTML
      <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
      <html>
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <style type="text/css"><!--
          * {
            font-family: Monaco;
          }
        --></style>
      </head>
      <body></body>
      </html>
      HTML
    end
    
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
    #$stderr = writer # for debugging it may be better to disable this (and look in Console.app)
    write_prompt
  end
  
  def document
    @web_view.mainFrame.DOMDocument
  end
  
  def command_line
    document.getElementById('command_line')
  end

# We will use certainly use it later so it let it commented out
#  def webView webView, shouldInsertText: text, replacingDOMRange: range, givenAction: action
#    if text == ?\n
#      perform_action
#      false
#    else
#      true
#    end
#  end
  
  def add_div(text)
    doc = document
    div = doc.createElement('div')
    div.innerText = text
    doc.body.appendChild(div)
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

    # webView:shouldInsertText:replacingDOMRange:givenAction: is not powerful enough for us
    # to do all our work so we add our keyDown method on the firstResponder (a WebHTMLView, child of the WebView)
    responder = @win.firstResponder
    # we must not install our callback more than once
    return if responder.respond_to?(:base_key_down)
    class << responder
      attr_writer :action_performer
      alias :base_key_down :keyDown
      def keyDown(e)
        # if the user presses Return, the entered text is evaluated,
        # but if also presses Alt, a carriage return is inserted
        if e.characters == ?\r and (e.modifierFlags & NSAlternateKeyMask == 0)
          @action_performer.perform_action
        else
          base_key_down(e)
        end
      end
    end
    responder.action_performer = self
  end
  
  def perform_action
    @line_num += 1
    command = command_line.innerText.tr(' ', ' ') # replace non breakable spaces by normal spaces
    if command.empty?
      write_prompt
      return
    end

    eval_file = __FILE__
    eval_line = -1
    begin
      # eval_line must be exactly the line where the eval call occurs
      eval_line = __LINE__; value = eval(command, @binding, 'macirb', @line_num)
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
