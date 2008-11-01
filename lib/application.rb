require 'hotcocoa'
framework 'webkit'

class Application
  include HotCocoa
  
  def start
    @line_num = 1
    @binding = TOPLEVEL_BINDING
    
    def base_html
      return <<-HTML
      <html>
      <body>
        <table>
          <tr>
            <td style="vertical-align: top;">&gt;&gt;</td>
            <td style="width: 100%;"><div id="command_line" contentEditable="true"></div></td>
          </tr>
        </table>
        <script type="text/javascript"><!--
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
        @web_view = web_view(:layout => {:expand =>  [:width, :height]})
        @web_view.mainFrame.loadHTMLString base_html, baseURL:nil
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
  
  def perform_action
    @line_num += 1
    command = @command_line.to_s
    return if command.empty?
    eval_file = __FILE__
    eval_line = -1
    begin
      eval_line = __LINE__; value = eval(command, @binding, 'macirb', @line_num-1)
      @display.text = value.inspect
    rescue Exception => e
      backtrace = e.backtrace
      i = backtrace.index { |l| l.index("#{eval_file}:#{eval_line}") }
      puts "#{eval_file}:#{eval_line}"
      puts i
      backtrace = backtrace[0..i-1] if i
      @display.text = "#{e.class.name}: #{e.message}\n#{backtrace.join("\n")}"
    end
    @command_line.text = ''
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
