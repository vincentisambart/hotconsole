require 'hotcocoa'
framework 'webkit'

# TODO:
# - autoscroll
# - focus
# - stdout/stderr, later stdin
class Application
  include HotCocoa
  
  def start
    @line_num = 0
    @binding = TOPLEVEL_BINDING
    
    def base_html
      return <<-HTML
      <html>
      <head>
        <style type="text/css"><!--
        --></style>
      </head>
      <body>
        <div id="display"></div>
        <table id="input_table">
          <tr>
            <td style="vertical-align: top;">&gt;&gt;</td>
            <td style="width: 100%;"><div id="command_line" contentEditable="true"></div></td>
          </tr>
        </table>
        <script type="text/javascript"><!--
        // TODO: do it in Ruby (but must wait for the document to be loaded)
        var command_line = document.getElementById('command_line');
        command_line.focus();
        //var selection = window.getSelection();
        //selection.setBaseAndExtent(command_line, 0, command_line, command_line.innerText.length);
        //selection.deleteFromDocument();
        --></script>
      </body>
      </html>
      HTML
    end
    
    application :name => "MacIrb" do |app|
      app.delegate = self

      window :frame => [100, 100, 900, 500], :title => "MacIrb" do |win|
        win.will_close { exit }
        win.contentView.margin = 0
        @web_view = web_view(:layout => {:expand => [:width, :height]})
        @web_view.mainFrame.loadHTMLString base_html, baseURL:nil
        @web_view.editingDelegate = self
        win << @web_view
      end
#        @display = label(:text => '', :layout => {:expand => [:width, :height]})
#        @command_line = text_field(:layout => {:expand => [:width]})
#        win << @command_line
#        win << @display
#        @command_line.on_action do
#          self.perform_action
#        end
    end
  end
  
  def document
    @web_view.mainFrame.DOMDocument
  end
  
  def command_line
    document.getElementById('command_line')
  end
  
  def webView webView, shouldInsertText: text, replacingDOMRange: range, givenAction: action
    if text == ?\n
      #alert :message => "This is an alert!", :info => "#{command_line}"
      perform_action
      false
    else
      true
    end
    #alert :message => "This is an alert!", :info => "#{text.unpack('U*')}"
  end
  
  def add_div(text)
    doc = document
    div = doc.createElement('div')
    div.innerText = text
    doc.getElementById('display').appendChild(div)
  end
  
  def write_element(element)
    document.getElementById('display').appendChild(element)
  end
  
  def write_text(text)
    div = document.createElement('div')
    div.innerText = text
    write_element(div)
  end

  def write_old_prompt(text)
    table = document.createElement('table')
    row = table.insertRow(0)
    prompt = row.insertCell(-1)
    prompt.innerText = '>>'
    typed_text = row.insertCell(-1)
    typed_text.innerText = text
    write_element(table)
  end
  
  def scroll_to_bottom
    body = document.body
    body.scrollTop = body.scrollHeight
    @web_view.setNeedsDisplay true
  end

  def perform_action
    @line_num += 1
    command = command_line.innerText
    write_old_prompt(command)
    command_line.innerText = ''
    return if command.empty?

    eval_file = __FILE__
    eval_line = -1
    begin
      # eval_line must be exactly the line where the eval call occurs
      eval_line = __LINE__; value = eval(command, @binding, 'macirb', @line_num)
      add_div(value.inspect)
    rescue Exception => e
      backtrace = e.backtrace
      i = backtrace.index { |l| l.index("#{eval_file}:#{eval_line}") }
      backtrace = backtrace[0..i-1] if i
      add_div("#{e.class.name}: #{e.message}\n#{backtrace.join("\n")}")
    end
    scroll_to_bottom
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
