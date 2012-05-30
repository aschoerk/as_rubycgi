require 'cgi'
require 'net/http'
require 'uri'
require 'stringio'
require 'zlib'

HttpParams = Struct.new('Params',
                        :protocol,:host,:port,:path,:params,:send_header,:send_body,:recv_header,:recv_body,
                        :get,:post,:save,:plus,:minus)

class HttpProcessor
  def initialize(params)
    @params = params
  end
  def analyze_params
    return if not @params.params
    params = @params.params.split(/&/)
    param_hash = {}
    params.map { |p|
      assignment = p.split(/=/)
      if assignment.length == 1
        param_hash[assignment[0]] = ""
      elsif assignment.length == 2
        param_hash[assignment[0]] =CGI::unescape(assignment[1])
      end
      assignment
    }
    param_hash
  end

  def analyse_header
    return if not @params.send_header
    headers = @params.send_header.split(/\r\n|\n/)
    headers_hash = {}
    headers.map { |h|
      if h.index(":")
        assignment = h.split(/: /)
        if assignment.length == 1
          headers_hash[assignment[0].lstrip] = ""
        elsif assignment.length == 2
          headers_hash[assignment[0].lstrip] = assignment[1]
        end
        assignment
      else
        nil
      end
    }
    headers_hash
  end


  def decode_header(header)
    res = {}
    res['content-length'] = header['content-length']
    res['content-encoding'] = header['content-encoding']
    res['content-type'] = header['content-type']
    res['date'] = header['date']
    res
  end

  def hash_to_header_text(hash)
    res = ""
    hash.keys().each {|k|
      # next if not k or not hash[k]
      res += k
      res += ": "
      res += hash[k]
      res += "\r\n"
    }
    res
  end

  def gzip_inflate(body)
    # http://stackoverflow.com/questions/1361892/how-to-decompress-gzip-string-in-ruby
    Zlib::GzipReader.new(StringIO.new(body)).read
  end

  def process
    params = @params
    if (params.get)
      params.path = "/" if not params.path
      params.path = "/" + params.path if not params.path.start_with?("/")
      res = Net::HTTP.get(params.host,params.path,params.port)
      params.recv_body = res
    elsif (params.post)
      params.path = "/" if not params.path
      params.path = "/" + params.path if not params.path.start_with?("/")
      s = params.protocol + "://" + params.host + ":" + params.port.to_s + params.path
      # s = s + "?" + params.params if params.params and params.params.length > 0
      url = URI.parse(s)
      req = Net::HTTP::Post.new(url.path,analyse_header)
      req.set_form_data(analyze_params)
      res = Net::HTTP.new(url.host, url.port).start {|http|
        http.request(req)
      }

      header_hash = decode_header(res.header)
      params.recv_header =  hash_to_header_text header_hash
      if header_hash['content-encoding'] == "gzip"
        params.recv_body = gzip_inflate(res.body)
      else
        params.recv_body = res.body
      end

    end
    return params
  end
end

class CGI_builder
  def initialize (cgi)
    @cgi = cgi
  end
  def interpret_params
    res = HttpParams.new
    def cond_init(res, key, init = nil)
      res[key] = init if init
      if @cgi.key?(key.to_s)
        p = @cgi.params[key.to_s]
        if p.is_a?(Array)
          res[key] = p[0]
        else
          res[key] = p
        end
      end
    end
    cond_init(res,:protocol,'HTTP')
    cond_init(res,:host)
    cond_init(res,:port,'80')
    res.port = res.port.to_i
    cond_init(res,:path)
    cond_init(res,:params)
    cond_init(res,:send_header)
    cond_init(res,:send_body)
    cond_init(res,:recv_header)
    cond_init(res,:recv_body)
    cond_init(res,:get)
    cond_init(res,:post)
    cond_init(res,:save)
    cond_init(res,:plus)
    cond_init(res,:minus)
    return res
  end

  def initCGI
    params = interpret_params
    proc = HttpProcessor.new(params)
    params = proc.process
    cgi = @cgi
    cgi.out {
      cgi.head {
        cgi.title { "Http(s) Tester" } +
            cgi.style('type' => "text/css") {
              "\nbody { background-color:lightgrey;
                 margin-left:10px; }
          \n* { color:blue; }
          \nh1 { font-size:300%;
               color:darkgrey;
               font-style:italic;
               border-bottom:solid thin black; }
          \np,li  { font-size:110%;
               line-height:140%;
               font-family:Helvetica,Arial,sans-serif;
               letter-spacing:0.1em;
               word-spacing:0.3em; }
          \ntd input { color:black; background-color:lightgrey; font-style:normal; size=\"1\" }
          \ntd textarea { color:black; background-color:lightgrey; font-style:normal; size=\"1\" }
          \n.wrong { color:red; background-color:#FFCCCC; }
          \n.emptycell { background-color:pink; }
          \n.ok { color:blue; background-color:grey; }
          \n.buttons { color:black; background-color:grey; }

          \n#sudokutable { margin-left:50px}
          \n#navi { float:left; margin: 0 0 1em 1em; padding: 0 }
          \n#table { float:right }
          "
            }
      } +
          cgi.body {
            cgi.h1 { "Http(s) Tester" } +
                cgi.form('name' => "http_form") {
                  cgi.p {
                    "protocol: " + cgi.input('type' => 'text', 'name' => 'protocol', 'value' => params.protocol, 'size' => '5') +
                        "host: " + cgi.input('type' => 'text', 'name' => 'host', 'value' => params.host, 'size' => '20') +
                        "port: " + cgi.input('type' => 'text', 'name' => 'port', 'value' => params.port.to_s, 'size' => '2') +
                        cgi.input('type' => "submit", 'name' => "get", 'value' => "get") +
                        cgi.input('type' => "submit", 'name' => "post", 'value' => "post") + "||" +
                        cgi.input('type' => "submit", 'name' => "save", 'value' => "save") +
                        cgi.input('type' => "submit", 'name' => "+", 'value' => "plus") +
                        cgi.input('type' => "submit", 'name' => "-", 'value' => "minus") +
                        cgi.table {
                          cgi.tr{
                            cgi.td {"path: "} +
                            cgi.td { cgi.input('type' => 'text', 'name' => 'path', 'value' => params.path, 'size' => '60')}
                          } +
                          cgi.tr{
                            cgi.td {"params: "} +
                            cgi.td { cgi.input('type' => 'text', 'name' => 'params', 'value' => params.params, 'size' => '60')}
                          } +
                          cgi.tr {
                            cgi.td{""} + cgi.td{"send"} + cgi.td{"recv"}
                          } +
                          cgi.tr{
                            cgi.td {"header: "} +
                            cgi.td { cgi.textarea('name' => 'send_header', 'cols' => '70', 'rows' => '10') {params.send_header}} +
                            cgi.td { cgi.textarea('name' => 'recv_header', 'cols' => '70', 'rows' => '10') {params.recv_header}}
                          } +
                          cgi.tr{
                            cgi.td {"body: "} +
                            cgi.td { cgi.textarea('name' => 'send_body', 'cols' => '70', 'rows' => '10') {params.send_body}} +
                            cgi.td { cgi.textarea('name' => 'recv_body', 'cols' => '70', 'rows' => '10') {params.recv_body}}
                          }
                        }
                  }
                }
          }

    }
    return @cgi
  end

end

def initCGI(cgi)
  CGI_builder.new(cgi).initCGI
end

if __FILE__ == $0
  cgi = CGI.new("html3")
  initCGI(cgi)
end

