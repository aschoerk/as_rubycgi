#!/usr/bin/ruby -w
$:.unshift File.join(File.dirname(__FILE__),'.','')
require 'cgi'
if RUBY_VERSION >= "1.9"
  require 'csv'
  class FasterCSV < CSV
  end
else
  require 'faster_csv'
end



ConvParams = Struct.new('ConvParams',:towiki,:tocsv,:csv,:twiki)

def interpret_params(cgi)
  res = ConvParams.new
  res.towiki = cgi.key?("to_wiki")
  res.tocsv = cgi.key?("to_csv")
  if cgi.key? "csv"
    if cgi["csv"].is_a?(Array)
      res.csv = cgi["csv"][0]
    else
      res.csv = cgi["csv"]
    end
  end
  if cgi.key? "twiki"
    res.twiki = cgi["twiki"][0]
  end
  res
end


class CSV2Wiki

  def initialize(csvstring)
    @csv = csvstring
  end

  def analyze
    maxcollens = []

    FasterCSV.parse(@csv,{:col_sep => ';'}) {|row|
      # puts row
      colcount = 0
      row.each {|field|
        if maxcollens.length <= colcount
          maxcollens << 0
        end
        if field
          if maxcollens[colcount] < field.length
            maxcollens[colcount] = field.length
          end
        end
        colcount += 1
      }
      @maxcollens = maxcollens
    }
  end
  def to_wiki
    maxlen = @maxcollens.inject(0) {|a,el| a+ el }
    colwidth = ""
    @maxcollens.map {|el|
      colwidth << "," + (el * 100 / maxlen).to_s + "%"
      el
    }
    fixedheaders = 'sort="on" tableborder="0" cellpadding="1" cellspacing="3" headerbg="#D5CCB1" headercolor="#666666" datacolor="#333333" databg="#FAF0D4, #F3DFA8"'
    s = "%TABLE{#{fixedheaders}columnwidths=\"#{colwidth[1..-1]}\" headerrows=\"1\" sort=\"on\" headeralign=\"center\"}%\n"
    firstrow = true
    FasterCSV.parse(@csv,{:col_sep => ';'}) {|row|
      # puts row
      s << '|'
      row.each {|field|
        s << '*' if firstrow
        s << field.gsub(/(\s|\r|\n)+/,' ') if field
        s << ' ' if not field
        s << '*' if firstrow
        s << '|'
      }
      s << "\n"
      firstrow = false
    }
    s
  end
end


def initCGI(cgi)
  cgi.out {
    params = interpret_params(cgi)
    puts "inputparams" + params.to_s
    if (params.towiki)
      # params.twiki = csv_to_wiki(params.csv)
      conv = CSV2Wiki.new(params.csv)
      conv.analyze
      params.twiki = conv.to_wiki
    end
    if (params.tocsv)
      params.cs = wiki_to_csv(params.twiki)
    end
    cgi.html {
      cgi.head {
        cgi.title{"Some Conversion Tools"} +
        cgi.style('type'=>"text/css") {
         "\nbody { background-color:lightgrey;
                 margin-left:100px; }
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
        cgi.h1 {"CSV to Wiki-Table"} +
        cgi.form('name'=>"conversionform")  {
          cgi.table {
            cgi.tr {
              cgi.td { "CSV File"} +
                  cgi.td {
                    cgi.textarea('name'=>'csv','cols'=>'100','rows'=>'10') {params.csv}
                  }
            } +
            cgi.tr {
              cgi.td { "TWiki File"} +
                  cgi.td {
                    cgi.textarea('name'=>'edittable','cols'=>'100','rows'=>'10'){params.twiki}
                  }
            } +
            cgi.tr {
              cgi.td {
                cgi.input('type'=>"submit",'name'=>"to_wiki",'value'=>"to wiki")
                # + cgi.input('type'=>"submit",'name'=>"to_csv",'value'=>"to csv")
              }
            }
          }
        }
      }
    }
  }
  return cgi
end

if __FILE__ == $0
  cgi = CGI.new("html3")
  initCGI(cgi)
end

