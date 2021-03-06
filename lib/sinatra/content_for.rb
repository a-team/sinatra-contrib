require 'sinatra/base'

module Sinatra
  ##
  # = Sinatra::ContentFor
  #
  # Small extension for the Sinatra[http://sinatrarb.com] web framework
  # that allows you to use the following helpers in your views:
  #
  #     <% content_for :some_key do %>
  #       <chunk of="html">...</chunk>
  #     <% end %>
  #
  #     <%= yield_content :some_key %>
  #
  # This allows you to capture blocks inside views to be rendered later
  # in this request. For example, to populate different parts of your
  # layout from your view.
  #
  # When using this with the Haml rendering engine, you should do the
  # following:
  #
  #     - content_for :some_key do
  #       %chunk{ :of => "html" } ...
  #
  #     = yield_content :some_key
  #
  # Supported engines: Erb, Erubis, Haml and Slim.
  #
  # == And how is this useful?
  #
  # For example, some of your views might need a few javascript tags and
  # stylesheets, but you don't want to force this files in all your pages.
  # Then you can put <tt><% yield_content :scripts_and_styles %></tt> on
  # your layout, inside the <head> tag, and each view can call
  # <tt>content_for</tt> setting the appropriate set of tags that should
  # be added to the layout.
  module ContentFor
    # Capture a block of content to be rendered later. For example:
    #
    #     <% content_for :head do %>
    #       <script type="text/javascript" src="/foo.js"></script>
    #     <% end %>
    #
    # You can call +content_for+ multiple times with the same key
    # (in the example +:head+), and when you render the blocks for
    # that key all of them will be rendered, in the same order you
    # captured them.
    #
    # Your blocks can also receive values, which are passed to them
    # by <tt>yield_content</tt>
    def content_for(key, &block)
      @current_engine ||= :ruby
      content_blocks[key.to_sym] << [@current_engine, block]
    end

    # Render the captured blocks for a given key. For example:
    #
    #     <head>
    #       <title>Example</title>
    #       <%= yield_content :head %>
    #     </head>
    #
    # Would render everything you declared with <tt>content_for 
    # :head</tt> before closing the <tt><head></tt> tag.
    #
    # You can also pass values to the content blocks by passing them
    # as arguments after the key:
    #
    #     <%= yield_content :head, 1, 2 %>
    #
    # Would pass <tt>1</tt> and <tt>2</tt> to all the blocks registered
    # for <tt>:head</tt>.
    def yield_content(key, *args)
      content_blocks[key.to_sym].map { |e,b| capture(e, args, b) }.join
    end

    def self.capture
      @capture ||= {}
    end

    private

    # generated templates will be cached by Sinatra in production
    capture[:haml]   = "!= capture_haml(*args, &block)"
    capture[:erb]    = "<% yield(*args) %>"
    capture[:erubis] = "<%= yield(*args) %>"
    capture[:slim]   = "== yield(*args)"

    def capture(engine, args, block)
      @_out_buf, buf_was = nil, @_out_buf
      eval '_buf.clear if defined? _buf', block.binding
      render(engine, Sinatra::ContentFor.capture.fetch(engine), {}, :args => args, :block => block, &block)
    ensure
      @_out_buf = buf_was
    end

    def render(engine, *)
      @current_engine, engine_was = engine.to_sym, @current_engine
      super
    ensure
      @current_engine = engine_was
    end

    def content_blocks
      @content_blocks ||= Hash.new {|h,k| h[k] = [] }
    end
  end

  helpers ContentFor
end
