require 'cgi'

def initCGI(cgi)
  cgi.out {
    cgi.head {
      cgi.title {"test title"}
    } +
        cgi.body {
          cgi.h1 {"Test Header"}
        }
  }
  return cgi
end

if __FILE__ == $0
  cgi = CGI.new("html3")
  initCGI(cgi)
end

