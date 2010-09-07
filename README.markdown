# Template Streaming

Rails plugin which enables progressive rendering for templates.

## Background

A typical Rails client-side profile looks something like this:

![Typical Rails Profile][slow-profile]

In almost all cases, this is highly suboptimal, as many resources, such as
external stylesheets, are static and could be loaded by the client while it's
waiting for the server response.

The trick is to output the response *progressively*--flushing the stylesheet
link tags out to the client before it has rendered the rest of the
page. Depending on how other external resources such javascripts and images are
used, they too may be flushed out early, significantly reducing the time for the
page to become interactive.

The problem is Rails has never been geared to allow this. Most Rails
applications use layouts, which require rendering the content of the page before
the layout. Since the global stylesheet tag is usually in the layout, we can't
simply flush the rendering buffer from a helper method.

Until now.

With Template Streaming, simply add `:progressive => true` to your
`layout` call to invert the rendering order, and then call `flush` in
your templates whenever you wish to flush the output buffer to the
client. This gives profiles that look more like:

![Progressive Rendering Profile][fast-profile]

[slow-profile]: http://github.com/oggy/template_streaming/raw/master/doc/slow-profile.png
[fast-profile]: http://github.com/oggy/template_streaming/raw/master/doc/fast-profile.png

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
   cookie store!) should not be made in the view.
 * An exception during rendering cannot simply replace the body with a
   stacktrace or 500 page. (Solution to come.)

### Helpers

 * `flush` - flush what has been rendered in the current template out to the
    client immediately.
 * `push(data)` - send the given data to the client immediately.

These can only do their job if the underlying web server supports progressive
rendering via Rack. This has been tested successfully with [Mongrel][mongrel]
and [Passenger][passenger]. [Thin][thin] is only supported if the [Event Machine
Flush][event-machine-flush] gem is installed. WEBrick does not support
progressive rendering. [Please send me][contact] reports of success with other
web servers!

[mongrel]: http://github.com/fauna/mongrel
[passenger]: http://www.modrails.com
[thin]: http://github.com/macournoyer/thin
[event-machine-flush]: http://github.com/oggy/event_machine_flush
[contact]: mailto:george.ogata@gmail.com

### Controller

 * `layout 'name', :progressive => true` - render the layout before content.
 * `when_streaming_template` - defines a callback to be called during a `render`
   call when a template is streamed. This is *before* the body is rendered, or
   any data is sent to the client.

## Example

Conventional wisdom says to put your external stylesheets in the HEAD of your
page, and your external javascripts at the bottom of the BODY (markup in
[HAML][haml]):

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

With progressive rendering, however, this could be improved. As [Stoyan Stefanov
writes][stefanov], you can put your javascripts in the HEAD of your page if you
fetch them via AJAX and append them to the HEAD of your page dynamically. This
also reduces the time for the page to become interactive (e.g., scrollable),
giving an even greater perceived performance boost.

Of course, rather than using an external library for the AJAX call, we can save
ourselves a roundtrip by defining a `getScript` function ourselves in a small
piece of inline javascript. This is done by `define_get_script`
below. `get_script` then includes a call to this function which fetches the
script asynchronously, and then appends the script tag to the HEAD.

### `config/routes.rb`

    ActionController::Routing::Routes.draw do |map|
      map.root :controller => 'test', :action => 'test'
    end

### `app/controllers/test_controller.rb`

    class TestController < ApplicationController
      layout 'application', :progressive => true

      def test
      end
    end

### `app/views/layouts/application.html.haml`

    !!! 5
    %html
      %head
        = define_get_script
        = stylesheet_link_tag 'one'
        = stylesheet_link_tag 'two'
        = get_script 'one'
        = get_script 'two'
     %body
        - flush
        = yield

### `app/views/test/test.html.haml`

    ...content...

### `app/helpers/application_helper.rb`

    module ApplicationHelper
      def define_get_script
        javascript_tag do
          File.read(Rails.public_path + '/javascripts/get_script.js')
        end
      end

      def get_script(url)
        javascript_tag do
          "$.getScript('#{javascript_path(url)}');"
        end
      end
    end

### `public/javascripts/get_script.js`

    //
    // Written by Sam Cole. See http://gist.github.com/364746 for more info.
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

The second profile was created using this code.

[haml]: http://haml-lang.com
[stefanov]: http://www.yuiblog.com/blog/2008/07/22/non-blocking-scripts
[get-script]: http://gist.github.com/364746

## Note on Patches/Pull Requests

 * Bug reports: http://github.com/oggy/template_streaming/issues
 * Source: http://github.com/oggy/template_streaming
 * Patches: Fork on Github, send pull request.
   * Ensure patch includes tests.
   * Leave the version alone, or bump it in a separate commit.

## Copyright

Copyright (c) 2010 George Ogata. See LICENSE for details.
