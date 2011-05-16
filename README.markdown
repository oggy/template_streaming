# Template Streaming

Progressive rendering for Rails.

## Background

A typical Rails client-side profile looks something like this:

![Typical Rails Profile][slow-profile]

This is highly suboptimal. Many resources, such as external stylesheets, are
completely static and could be loaded by the client while it's waiting for the
server response.

The trick is to *stream* the response--flushing the markup for the static
resources to the client before it has rendered the rest of the page. In
addition to being able to render styles and images earlier, the browser can
download javascripts, making the page responsive to input events sooner.

The main barrier to this in Rails is that layouts are rendered before the
content of the page. The control flow must thus be altered to render the page in
the order the client needs to receive it - layout first.

With streaming, your profiles can look more like this:

![Progressive Rendering Profile][fast-profile]

[slow-profile]: https://github.com/oggy/template_streaming/raw/master/doc/slow-profile.png
[fast-profile]: https://github.com/oggy/template_streaming/raw/master/doc/fast-profile.png

## How

Just add the `template_streaming` gem to your application, and add a `stream`
call for the actions you'd like to stream. For example, to stream just the
`index` action of your `HomeController`, it would look like this:

    class HomeController
      stream :only => :index

      def index
        ...
      end
    end

To stream everything, just add `stream` to your `ApplicationController`.

Now you may pepper `flush` calls strategically throughout your views to force a
flush, such as just after the stylesheet and javascript tags. `flush` may occur
in both templates and their layouts.

## API

The API is simple, but it's important to understand the change in control flow
when a template is streamed. A controller's `render` no longer results in
rendering templates immediately; instead, `response.body` is set to a
`StreamingBody` object which will render the template when the server calls
`#each` on the body *after* the action returns, as per the Rack specification.
This has several implications:

 * Anything that needs to inspect or modify the body should be moved to a
   middleware.
 * Modifications to cookies (this includes the flash and session if using the
   cookie store) must not be made in the view. In fact, these objects will be
   frozen when streaming.
 * An exception during rendering cannot result in a 500 response, as the headers
   will have already been sent. Instead, the innermost partial which contains an
   error will simply render nothing, and error information is injected into the
   foot of the page in development mode.

### Helpers

 * `flush` - flush what has been rendered in the current template out to the
    client immediately.
 * `push(data)` - send the given data to the client immediately.

## Support

Template Streaming currently only supports Rails 2.3.11. Rails 3.0 support is
planned in the near future. Rails 3.1 will ship with support for streaming. This
gem will be updated to meet the API of Rails 3.1 as it evolves, to help you
migrate.

Streaming also requires a web server that does not buffer Rack responses. It has
been tested **successfully** with [Passenger][passenger], [Unicorn][unicorn],
and [Mongrel][mongrel]. Note that Unicorn requires the `:tcp_nopush => false`
configuration option. [Thin][thin] is only supported if the
[Event Machine Flush][event-machine-flush] gem is installed. WEBrick does
**not** support streaming. [Please send me][contact] your experiences with other
web servers!

[passenger]: http://www.modrails.com
[unicorn]: http://unicorn.bogomips.org/
[mongrel]: https://github.com/fauna/mongrel
[thin]: https://github.com/macournoyer/thin
[event-machine-flush]: https://github.com/oggy/event_machine_flush
[contact]: mailto:george.ogata@gmail.com

### Controller

Class methods:

 * `stream` - stream responses for these actions. Takes `:only` or `:except`
   options, like `before_filter`.

 * `when_streaming_template` - registers a callback to be called during `render`
   when rendering progressively. This is before the body is rendered, or any
   data is sent to the client.

Instance methods:

 * `render` has been modified to accept a `:stream` option. If true, the
   response will be streamed, otherwise it won't. This overrides the setting set
   by the `stream` method above.

### Error Recovery

As mentioned above, headers are sent to the client before view rendering starts,
which means it's not possible to send an error response in the event of an
uncaught exception. Instead, the innermost template which raised the error
simply renders nothing. This has the added advantage of minimizing the impact on
your visitors, as the rest of the page will render fine.

When an error is swallowed like this, it is passed to an error hander callback,
which you can set as follows.

    TemplateStreaming.on_streaming_error do |controller, exception|
      ...
    end

This is where you should hook in your error notification system. Errors are also
logged to the application log.

In addition, in development mode, error information is injected into the foot of
the page. This is presented over the top of the rendered page, so the result
looks much like when not streaming.

## Streaming Templates Effectively

Conventional wisdom says to put your external stylesheets in the HEAD of your
page, and your external javascripts at the bottom of the BODY (markup in
[HAML][haml]):

[haml]: http://haml-lang.com

### `app/views/layouts/application.html.haml`

    !!! 5
    %html
      %head
        = stylesheet_link_tag 'one'
        = stylesheet_link_tag 'two'
     - flush
     %body
       = yield
       = javascript_include_tag 'one'
       = javascript_include_tag 'two'

When streaming, however, you can do better: put the javascripts at the top of
the page too, and fetch them *asynchronously*. This can be done by appending a
script tag to the HEAD of the page in a small piece of inline javascript:

### `app/views/layouts/application.html.haml`

    !!! 5
    %html
      %head
        = stylesheet_link_tag 'one'
        = stylesheet_link_tag 'two'
        = javascript_tag do
          = File.read(Rails.public_path + '/javascripts/get_script.js')
          $.getScript('#{javascript_path('jquery')}');
          $.getScript('#{javascript_path('application')}');
    %body
        - flush
        = yield

### `public/javascripts/get_script.js`

    //
    // Credit: Sam Cole [https://gist.github.com/364746]
    //
    window.$ = {
      getScript: function(script_src, callback) {
        var done = false;
        var head = document.getElementsByTagName("head")[0] || document.documentElement;
        var script = document.createElement("script");
        script.src = script_src;
        script.onload = script.onreadystatechange = function() {
          if ( !done && (!this.readyState ||
              this.readyState === "loaded" || this.readyState === "complete") ) {
            if(callback) callback();

            // Handle memory leak in IE
            script.onload = script.onreadystatechange = null;
            if ( head && script.parentNode ) {
              head.removeChild( script );
            }

            done = true;
          }
        };
        head.insertBefore( script, head.firstChild );
      }
    };

If you have inline javascript that depends on the fetched scripts, you'll need
to delay its execution until the scripts have been run. You can do this by
wrapping the javascript in a function, with a guard which will delay execution
until the script is loaded, unless the script has already been loaded. Example:

### Layout

    !!! 5
    %html
      %head
        = stylesheet_link_tag 'one'
        = stylesheet_link_tag 'two'
        = javascript_tag do
          = File.read(Rails.public_path + '/javascripts/get_script.js')
          $.getScript('#{javascript_path('jquery')}', function() {
            window.script_loaded = 1;

            // If the inline code has been loaded (but not yet run), run it
            // now. Otherwise, it will be run immediately when it's available.
            if (window.inline)
              inline();
          });
    %body
        - flush
        = yield

### View

    - javascript_tag do
      window.inline() {
        // ... inline javascript code ...
      }

      // If the script is already loaded, run it now. Otherwise, the callback
      // above will run it after the script is loaded.
      if (window.script_loaded)
        inline();

### In `public/javascripts/get_script.js`

    //
    // Credit: Sam Cole [https://gist.github.com/364746]
    //
    window.$ = {
      getScript: function(script_src, callback) {
        var done = false;
        var head = document.getElementsByTagName("head")[0] || document.documentElement;
        var script = document.createElement("script");
        script.src = script_src;
        script.onload = script.onreadystatechange = function() {
          if ( !done && (!this.readyState ||
              this.readyState === "loaded" || this.readyState === "complete") ) {
            if(callback) callback();

            // Handle memory leak in IE
            script.onload = script.onreadystatechange = null;
            if ( head && script.parentNode ) {
              head.removeChild( script );
            }

            done = true;
          }
        };
        head.insertBefore( script, head.firstChild );
      }
    };

## Contributing

 * [Bug reports](https://github.com/oggy/template_streaming/issues)
 * [Source](https://github.com/oggy/template_streaming)
 * Patches: Fork on Github, send pull request.
   * Include tests where practical.
   * Leave the version alone, or bump it in a separate commit.

## Copyright

Copyright (c) George Ogata. See LICENSE for details.
