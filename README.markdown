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

Template Streaming circumvents the template rendering order by introducing
*prelayouts*. A prelayout wraps a layout, and is rendered *before* the layout
and its content. By using the provided `flush` helper prior to yielding in the
prelayout, one can now output content early in the rendering process, giving
profiles that look more like:

  ![Progressive Rendering Profile][fast-profile]

Also provided is a `#push(data)` method which can be used to send extra tags to
the client as their need becomes apparent. For instance, you may wish to `push`
out a stylesheet link tag only if a particular partial is reached which contains
a complex widget.

[fast-profile]: http://github.com/oggy/template_streaming/tree/master/doc/fast-profile.png
[slow-profile]: http://github.com/oggy/template_streaming/tree/master/doc/slow-profile.png

## Example

Conventional wisdom says to put your external stylesheets in the HEAD of your
page, and your external javascripts at the bottom of the BODY (markup in
[HAML][haml]):

### `app/views/prelayouts/application.html.haml`

    !!! 5
    %html
      %head
        = stylesheet_link_tag 'one'
        = stylesheet_link_tag 'two'
     - flush
     = yield

### `app/views/layouts/application.html.haml`

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

### `app/views/prelayouts/application.html.haml`

    !!! 5
    %html
      %head
        = define_get_script
        = stylesheet_link_tag 'one'
        = stylesheet_link_tag 'two'
        = get_script 'one'
        = get_script 'two'
     - flush
     = yield

### `app/views/layouts/application.html.haml`

    %body
      = yield

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
