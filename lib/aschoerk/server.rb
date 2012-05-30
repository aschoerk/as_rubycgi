#!/usr/bin/env ruby
$:.unshift File.join(File.dirname(__FILE__),'.','')
require 'webrick'
require 'cgi'
require 'stringio'

$cgi_input = nil

class CGI
  def stdoutput
    @str_output = StringIO.new if not defined? @str_output
    @str_output
  end
  def stdinput
    $cgi_input
  end
  def to_s
    return @str_output.string if defined? @str_output
    "EMPTY"
  end
end

class CgiTester < WEBrick::HTTPServlet::AbstractServlet

  def initialize(server)
    super
    @script_filename = "inprocess_script"
    @tempdir = server[:TempDir]
  end

  def do_GET(req, res)
    if RUBY_VERSION >= "1.9"
      load "#{ARGF.argv[0]}"
    else
      load "#{$ARGV[0]}"
    end

    cgi_in = Tempfile.new("webrick.cgi_in.", @tempdir)
    meta = req.meta_vars
    ENV.keys.each{|name| ENV.delete(name) }
    meta.each{|k, v| ENV[k] = v if v }
    if req.body and req.body.size > 0
      cgi_in.write(req.body)
    end
    cgi_in.close
    $cgi_input =  File.open(cgi_in.path)
    cgi = initCGI(CGI.new("html3"))
    $cgi_input.close
    content = cgi.to_s
    res.status = 200
    ix = content.index("\r\n\r\n")
    res.content_type = 'text/html'
    res.content_length = content.length
    res.content_length -= ix if ix
    res.body = content[ix..-1]

  end

  alias do_POST do_GET

end


include WEBrick
s = HTTPServer.new(
    :Port => 8081
)

s.mount "/cgitester", CgiTester

trap("INT") { s.shutdown }
s.start


