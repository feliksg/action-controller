require "csv"
require "json"
require "xml"
require "yaml"

module ActionController::Responders
  STATUS_CODES = {
    # 1xx informational
    continue:            100,
    switching_protocols: 101,
    processing:          102,

    # 2xx success
    ok:                            200,
    created:                       201,
    accepted:                      202,
    non_authoritative_information: 203,
    no_content:                    204,
    reset_content:                 205,
    partial_content:               206,
    multi_status:                  207,
    already_reported:              208,
    im_used:                       226,

    # 4xx client error
    bad_request:                     400,
    unauthorized:                    401,
    payment_required:                402,
    forbidden:                       403,
    not_found:                       404,
    method_not_allowed:              405,
    not_acceptable:                  406,
    proxy_authentication_required:   407,
    request_timeout:                 408,
    conflict:                        409,
    gone:                            410,
    length_required:                 411,
    precondition_failed:             412,
    payload_too_large:               413,
    uri_too_long:                    414,
    unsupported_media_type:          415,
    range_not_satisfiable:           416,
    expectation_failed:              417,
    misdirected_request:             421,
    unprocessable_entity:            422,
    locked:                          423,
    failed_dependency:               424,
    upgrade_required:                426,
    precondition_required:           428,
    too_many_requests:               429,
    request_header_fields_too_large: 431,
    unavailable_for_legal_reasons:   451,

    # 5xx server error
    internal_server_error:           500,
    not_implemented:                 501,
    bad_gateway:                     502,
    service_unavailable:             503,
    gateway_timeout:                 504,
    http_version_not_supported:      505,
    variant_also_negotiates:         506,
    insufficient_storage:            507,
    loop_detected:                   508,
    not_extended:                    510,
    network_authentication_required: 511,
  }

  REDIRECTION_CODES = {
    # 3xx redirection
    multiple_choices:   300,
    moved_permanently:  301,
    found:              302,
    see_other:          303,
    not_modified:       304,
    use_proxy:          305,
    temporary_redirect: 307,
    permanent_redirect: 308,
  }

  MIME_TYPES = {
    binary: "application/octet-stream",
    csv:    "text/csv",
    json:   "application/json",
    xml:    "application/xml",
    text:   "text/plain",
    html:   "text/html",
    yaml:   "text/yaml",
  }

  macro render(status = :ok, json = nil, xml = nil, html = nil, yaml = nil, text = nil, binary = nil, csv = nil)
    response = self.response
    {% if status != :ok || status != 200 %}
      response.status_code = {{STATUS_CODES[status] || status}}
    {% end %}

    ctype = response.headers["Content-Type"]?

    {% if json %}
      response.content_type = MIME_TYPES[:json] unless ctype

      {% if json.is_a?(String) %}
        output = {{json}}
      {% else %}
        output = ({{json}}).to_json
      {% end %}
    {% end %}

    {% if xml %}
      response.content_type = MIME_TYPES[:xml] unless ctype
      output = {{xml}}
    {% end %}

    {% if html %}
      response.content_type = MIME_TYPES[:html] unless ctype
      output = {{html}}
    {% end %}

    {% if yaml %}
      response.content_type = MIME_TYPES[:yaml] unless ctype
      {% if yaml.is_a?(String) %}
        output = {{yaml}}
      {% else %}
        output = ({{yaml}}).to_yaml
      {% end %}
    {% end %}

    {% if text %}
      response.content_type = MIME_TYPES[:text] unless ctype
      output = {{text}}
    {% end %}

    {% if binary %}
      response.content_type = MIME_TYPES[:binary] unless ctype
      output = {{binary}}
    {% end %}

    {% if csv %}
      response.content_type = MIME_TYPES[:csv] unless ctype
      output = {{csv}}
    {% end %}

    {% if json || xml || html || yaml || text || binary || csv %}
        response << output unless self.request.method == "HEAD"
    {% end %}

    @render_called = true
    return
  end

  macro head(status)
    render({{status}})
  end

  macro redirect_to(path, status = :found)
    response = self.response
    response.status_code = {{REDIRECTION_CODES[status] || status}}
    response.headers["Location"] = {{path}}
    @render_called = true
    return
  end

  macro respond_with(&block)
    resp = SelectResponse.new(response, accepts_formats)
    resp.responses do
      {{block.body}}
    end
    resp.build_response
    @render_called = true
    return
  end

  ACCEPT_SEPARATOR_REGEX = /,\s*/

  # Extracts the mime types from the Accept header
  def accepts_formats
    accept = request.headers["Accept"]?
    if accept && !accept.empty?
      accepts = accept.split(";").first?.try(&.split(ACCEPT_SEPARATOR_REGEX))
      return accepts if accepts && accepts.any?
    end
    return [] of String
  end

  # Helper class for selecting the response to render / execute
  class SelectResponse
    def initialize(@response : HTTP::Server::Response, formats)
      @accepts = SelectResponse.accepts(formats)
      @options = {} of Symbol => Proc(String)
    end

    @accepts : Hash(Symbol, String)
    getter options

    # Build a list of possible responses to the request
    def responses
      with self yield
    end

    macro html(obj = nil, &block)
      {% if block.is_a?(Nop) %}
        options[:html] = ->{ {{obj}} }
      {% else %}
        options[:html] = ->{
          {{ block.body }}
        }
      {% end %}
    end

    macro xml(obj = nil, &block)
      {% if block.is_a?(Nop) %}
        options[:xml] = ->{ {{obj}} }
      {% else %}
        options[:xml] = ->{
          {{ block.body }}
        }
      {% end %}
    end

    macro json(obj = nil, &block)
      {% if block.is_a?(Nop) %}
        options[:json] = ->{
          output = {{obj}}
          {% if obj.is_a?(String) %}
            output
          {% else %}
            output.to_json
          {% end %}
        }
      {% else %}
        options[:json] = ->{
          {{ block.body }}
        }
      {% end %}
    end

    macro yaml(obj = nil, &block)
      {% if block.is_a?(Nop) %}
        options[:yaml] = ->{
          output = {{obj}}
          {% if obj.is_a?(String) %}
            output
          {% else %}
            output.to_yaml
          {% end %}
        }
      {% else %}
        options[:yaml] = ->{
          {{ block.body }}
        }
      {% end %}
    end

    macro text(obj = nil, &block)
      {% if block.is_a?(Nop) %}
        options[:text] = ->{ {{obj}} }
      {% else %}
        options[:text] = ->{
          {{ block.body }}
        }
      {% end %}
    end

    macro binary(obj = nil, &block)
      {% if block.is_a?(Nop) %}
        options[:binary] = ->{ {{obj}} }
      {% else %}
        options[:binary] = ->{
          {{ block.body }}
        }
      {% end %}
    end

    macro csv(obj = nil, &block)
      {% if block.is_a?(Nop) %}
        options[:csv] = ->{ {{obj}} }
      {% else %}
        options[:csv] = ->{
          {{ block.body }}
        }
      {% end %}
    end

    # Respond appropriately
    def build_response
      found = nil

      # Search for the first acceptable format
      if @accepts.any?
        @accepts.each do |format, mime|
          option = @options[format]?
          if option
            @response.content_type = mime
            found = option
            break
          end
        end

        if found
          @response << found.call
        else
          @response.status_code = 406 # not acceptable
        end
      else
        # If no format specified then default to the first format specified
        opt = @options.first
        format = opt[0]
        data = opt[1].call

        @response.content_type = MIME_TYPES[format]
        @response << data
      end
    end

    ACCEPTED_FORMATS = {
      "text/html":                :html,
      "application/xml":          :xml,
      "text/xml":                 :xml,
      "application/json":         :json,
      "text/plain":               :text,
      "application/octet-stream": :binary,
      "text/yaml":                :yaml,
      "text/x-yaml":              :yaml,
      "application/yaml":         :yaml,
      "application/x-yaml":       :yaml,
      "text/csv":                 :csv,
    }

    # Creates an ordered list of supported formats with requested mime types
    def self.accepts(accepts_formats)
      formats = {} of Symbol => String
      accepts_formats.each do |format|
        data_type = ACCEPTED_FORMATS[format]?
        if data_type && formats[data_type]?.nil?
          formats[data_type] = format
        end
      end
      formats
    end
  end
end
