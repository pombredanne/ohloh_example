#!/usr/bin/ruby

require 'cgi'
require 'net/http'
require 'open-uri'
require 'timeout'

require 'rexml/document'
require 'rexml/parsers/streamparser'
include REXML

#############################################
# XML parser that specifically parses
# the return result of a 'language' query

class XmlParser
  attr_reader :items_available, :items_returned

  def initialize()
    @stack    = Array.new()
    @object   = Hash.new()
    @language = nil

    @items_available = 0
    @items_returned  = 0

    @in_language     = false
  end

  def parse(xml)
    Document.parse_stream(xml, self)

  rescue Exception => e
    puts("XML error: #{e.message}")

  ensure
    return @object
  end

  def tag_start(name, attr)
    if name == 'language' && !@in_language
      @language = Hash.new()
      @in_language = true
    end
    @stack << { :name => name }
  end

  def text(text)
    text.sub!(/^\s+/, ' ')
    return if text == ' '

    @stack[-1][:text] = text
  end

  def tag_end(name)
    # Pop stack
    element = @stack[-1]

    if name == 'items_available'
      @items_available = element[:text].to_i
    elsif name == 'items_returned'
      @items_returned = element[:text].to_i
    end

    if @in_language && name == 'language'
      @in_language = false
      @object[@language['nice_name']] = @language
    elsif @in_language
      @language[name] = element[:text]
    end
  end

  # required but not currently used
  def cdata(cdata_text) end
  def xmldecl(*args) end
  def comment(*arg) end
  def entity(*args) end
  def instruction(*args) end
end

###############################################
# API test - query statistics for a language

class OhlohTest
  API_KEY = 'AcUQKRJKWMXxzEsEvpiyrQ'

  def initialize()
  end

  def run(query)
    list = build_language_list(query)
    report(list, query)
  end

  private

  ################################
  # Report language statsitics
  def report(list, query)
    items = list.size()

    if items == 0
      puts("No languages matching '#{query}' found")
    else
      puts("#{items} languages matching '#{query}' found:")
      puts

      list.each_pair do |name, stats|
        puts("#{name}")
        puts("   Category:     #{stats['category']}")
        puts("   Projects:     #{stats['projects']}")
        puts("   Contributors: #{stats['contributors']}")
        puts("   Commits:      #{stats['commits']}")
        puts
      end
    end
  end

  ################################
  # Build internal language list
  def build_language_list(query)
    items_available = 0
    items_read      = 0
    page            = 2
    list            = nil

    # Get first page
    body = http_get("http://www.ohloh.net/languages.xml?api_key=#{API_KEY}&query=#{query}")

    # Create XML parser and parse first page
    xmlp = XmlParser.new()
    list = xmlp.parse(body)

    # Get initial count
    items_available = xmlp.items_available
    items_read      = xmlp.items_returned
    page            = 2

    # Read in more pages until all available items are read in
    while items_read < items_available
      body = http_get("http://www.ohloh.net/languages.xml?api_key=#{API_KEY}&page=#{page}&query=#{query}")

      # Parse more pages page
      list = xmlp.parse(body)

      items_read += xmlp.items_returned
      page       += 1
    end

    return list
  end

  ################################
  # Send HTTP request
  def http_get(uri_string)
    uri          = URI.parse(uri_string)
    http_host    = uri.host
    http_path    = uri.path
    http_port    = uri.port
    query_string = uri.query
    http_timeout = 3.0
    http_header  = {'User-Agent' => 'Mozilla'}

    http_response = nil
    body          = ''
    
    begin
      Timeout::timeout(http_timeout) do
        http = Net::HTTP.start(http_host, http_port)
        http_response = http.get("#{http_path}?#{query_string}", http_header)
        
        case http_response
        when Net::HTTPSuccess
          http_status = true
          body = http_response.body
        when Net::HTTPRedirection
          redirect_uri = http_response['Location']
          return http_get(redirect_uri)
        end
      end
      
    rescue Exception => e
      puts("Error: #{e.message}")

    ensure
      return body
    end
  end
end

begin
  if ARGV.size() > 0
    test = OhlohTest.new()
    test.run(ARGV[0])
  else
    puts("Usage: ohloh_example <language name>")
  end
  
rescue Exception => e
  puts("Error: #{e.message}")
end
