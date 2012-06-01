#!/usr/bin/ruby -w
$:.unshift File.join(File.dirname(__FILE__), '.', '')
require 'cgi'
require 'xmlsimple'


@@test_mode = true

class Geo
  Coordinate = Struct.new('Coordinate', :lat, :lon)
  # From Wikipedia:
  # The nautical mile is a unit of length corresponding approximately to one minute of arc of latitude along any meridian.
  # Useful conversions:
  # 1 Arc Minute = 1 Nautical Mile
  # 1 Nautical Mile = 1.15078 Miles
  # 1 Nautical Mile = 6076.12 Feet
  # 1 Nautical Mile = 1852.00 Metres
  # 1 Arc Second = 30.866... Metres

  # The radius of the Earth only varies by 0.3% from Equator to Pole, so we can treat it as a sphere for these purposes.
  # The Vincenty distance formula is included for when this discrepancy is not acceptable.
  # Earth Equatorial Radius: 6 378 137 Metres
  # Earth Polar Radius: 6 356 752.3 Metres
  # Based on these, average radius: 6 367 444.5 Metres

  EARTH_RADIUS = 6367444.5
  EARTH_CIRCUMFERENCE = 2 * Math::PI * EARTH_RADIUS

  DEGREE_TO_RADIAN = 0.0174532925199433  # 2 * Math::PI / 360

  M_IN_KM = 1000
  M_IN_MI = 1609.344
  # Adapted from GeoRuby. I lifted this because I didn't think
  # it warranted adding a gem dependency to Cartographer. Thanks GeoRuby!
  # Returns distance in metres. Assumes spherical Earth.
  def self.haversine_distance(from, to)
    radlat_from = from.lat * DEGREE_TO_RADIAN
    radlat_to = to.lat * DEGREE_TO_RADIAN

    dlat = (to.lat - from.lat) * DEGREE_TO_RADIAN
    dlon = (to.lon - from.lon) * DEGREE_TO_RADIAN

    a = Math.sin(dlat/2)**2 + Math.cos(radlat_from) * Math.cos(radlat_to) * Math.sin(dlon/2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
    EARTH_RADIUS * c
  end



  def self.calc_intermediate_point(s,e,in_distance)
    x = haversine_distance(s,Coordinate.new(s.lat,e.lon))
    y = haversine_distance(s,Coordinate.new(e.lat,s.lon))
    qlen = (x * x) + (y * y)
    sgny = (e.lat >= s.lat ? 1 : -1)
    sgnx = (e.lon >= s.lon ? 1 : -1)
    if y != 0
      denom = (x*x)/(y*y) +1
      qdy = (in_distance*in_distance)/denom
      dy = Math::sqrt(qdy)
      dlat = dy * 180 / (EARTH_RADIUS * Math::PI)
      dx = (x / y) * dy
      dlon = dx * 180 / (EARTH_RADIUS * Math::PI * Math::cos((s.lat + dlat * sgny) * DEGREE_TO_RADIAN))
      Coordinate.new(s.lat + dlat*sgny, s.lon + dlon*sgnx)
    else
      dx = in_distance * 180 / (EARTH_RADIUS * Math::PI * Math::cos(s.lat * DEGREE_TO_RADIAN))
      Coordinate.new(s.lat, s.lon + dx*sgnx)
    end
  end

  def self.map_track_to_gpx(track)
    track.map { |el|
      {'lat' => el.lat.to_s, 'lon' => el.lon.to_s}
    }
  end

  def self.calc_fixed_distance_points(track, distance)
    nextdistance = distance
    current = 0
    res = []
    track.inject(nil) {|memo, pt|
      # puts "pt1: " + memo.to_s + " pt2: " + pt.to_s
      if memo
        len = haversine_distance(memo,pt)
        nextcurrent = current + len
        if nextcurrent > nextdistance
          diff = nextdistance - current
          res << calc_intermediate_point(memo,pt,diff)
          nextdistance += distance
        end
        current = nextcurrent
      end
      pt
    }
    res
  end

  def self.interpret_coordinate_string(s)
    res = Coordinate.new
    tmp = s.split(/,/)
    res.lat = tmp[1].to_f
    res.lon = tmp[0].to_f
    res
  end

  def self.interpret_via_string(s)
    res = s.split(/ /)
    res.map! { |el| interpret_coordinate_string el }
    res
  end

  def self.length(track)
    len = 0
    track.inject(nil){|memo,el|
      if memo
        len += haversine_distance(memo,el)
      end
      el
    }
    len
  end


  def self.extract_track_from_gpx(gpx)
    xml = XmlSimple.xml_in(gpx)
    puts xml
    track = xml['trk'][0]['trkseg'][0]['trkpt']
    track.map { |pt|
      Coordinate.new(pt['lat'].to_f, pt['lon'].to_f)
    }
  end

  def self.extract_track_from_gml(gml)
    xml = XmlSimple.xml_in(gml)
    puts xml

    track = xml['Response'][0]['DetermineRouteResponse'][0]['RouteGeometry'][0]['LineString'][0]['pos']
    track.map { |pos|
      spl = pos.split(/ /)
      Coordinate.new(spl[1].to_f, spl[0].to_f)
    }
  end

  def self.create_src_gpx(track)
     %Q{<gpx xmlns="http://www.topografix.com/GPX/1/1" creator="www.OpenRouteService.org" xmlns:xsi="http://www.w4.org/2001/XMLSchema-instance" version="1.1" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
           <trk>
             <trkseg>
                <trkpt lon="8.3721544" lat="49.0455162" />
             </trkseg>
           </trk>
         </gpx>
        }
  end

  def self.create_kml(track, wpts)
    res = "<coordinates>"
    track.inject(res) {|a, pt|
      res += "\n"
      res += pt.lon.to_s
      res += ","
      res += pt.lat.to_s
      res += ",0"
    }
    res += "</coordinates>"
    wptsres = ""
    if wpts and wpts.length > 0
      (0...wpts.length).each {|i|
         wptsres += %Q{<Placemark>
                         <name>KM #{i+1}</name>
                         <Point><coordinates>#{wpts[i].lon},#{wpts[i].lat}</coordinates></Point>
                       </Placemark>
                      }
      }
    end

    %Q{<?xml version="1.0" encoding="UTF-8"?>
       <kml xmlns="http://www.opengis.net/kml/2.2">
       <Document>
         <name>convroute</name>
        <Style id="sn_ylw-pushpin">
            <LineStyle>
              <color>ffff5500</color>
              <width>2</width>
            </LineStyle>
          </Style>
         <Placemark>
           <name>track</name>
           <styleUrl>#sn_ylw-pushpin</styleUrl>
           <LineString>
              <extrude>1</extrude>
              <tessellate>1</tessellate>
              <altitudeMode>relativeToGround</altitudeMode>
              #{res}
           </LineString>
         </Placemark>
         #{wptsres}
       </Document>
      </kml>}
  end


end


class RouteConverter

  ConvParams = Struct.new('ConvParams', :kml, :src_url, :src_url_object, :src_gpx, :src_gpx_object, :src_track, :src_len, :distance, :smooth, :correct_via, :res_url, :res_gpx, :res_len)
  UrlInfo = Struct.new('UrlInfo', :address, :params, :start, :end, :via)

  def analyze_URL(url)
    url_info = UrlInfo.new
    param_start_index = url.index('?')
    url_info.address = url[0..param_start_index]
    params = url[(param_start_index+1)..-1].split(/&/)
    param_hash = {}
    params.map { |p|
      assignment = p.split(/=/)
      param_hash[assignment[0]] = CGI::unescape(assignment[1])
      assignment
    }
    url_info.start = Geo::interpret_coordinate_string param_hash['start']
    url_info.end = Geo::interpret_coordinate_string param_hash['end']
    url_info.via = Geo::interpret_via_string param_hash['via'] if param_hash['via']
    url_info.params = params
    url_info
  end

  def create_URL(params)
    src_url_object = params.src_url_object
    if src_url_object
      res = src_url_object.address
      src_url_object.params.each {|p|
        res << '&' if not res.end_with?('?')
        if @newvia and p.start_with?('via')
          res << 'via='
          @newvia.each {|p|
            res << '%20' if not res.end_with?('=')
            res << p.lon.to_s
            res << ','
            res << p.lat.to_s
          }
        else
          res << p
        end
      }
      params.res_url = res
      puts res
    end
  end


# interpretURL("http://openrouteservice.org/index.php?start=8.3866078,49.0263935&end=8.3876235,49.0264548&via=8.3881528,49.0268437%208.3881957,49.0294607%208.3885819,49.0314303%208.3834750,49.0341314%208.3787728,49.0356294%208.3775527,49.0364104%208.3772523,49.0381828%208.3772093,49.0412774%208.3649594,49.0497124%208.3570873,49.0541577%208.3594048,49.0515139%208.3678967,49.0415728%208.3700425,49.0399692%208.3717162,49.0383657%208.3751494,49.0360587%208.3762652,49.0351865%208.3766085,49.0350458%208.3763939,49.0328231%208.3758360,49.0282366%208.3754498,49.0229744%208.3751065,49.0215673%208.3816052,49.0214193%208.3830214,49.0209971%208.3855778,49.0207230%208.3866078,49.0220738%208.3872944,49.0250850%20&pref=Pedestrian&lang=en&noMotorways=false&noTollways=false")



  def interpret_params(cgi)
    def if_array_else_single(s)
      s.is_a?(Array) ? s[0] : s
    end
    res = ConvParams.new
    res.src_url = if_array_else_single cgi.params["srcurl"]
    #res.src_gpx = if_array_else_single cgi.params["srcgpx"]
    res.smooth = true # cgi.key?("smooth")
    res.correct_via = true # cgi.key?("correct_via")
    res.kml = cgi.key?("kml")
    begin
      res.distance = if_array_else_single(cgi.params['distance']).to_i
    rescue
      res.distance = 1000
    end
    begin
      res.src_url_object = analyze_URL(res.src_url)
    rescue
      res.distance = 1000
    end
    begin
      #res.src_track = Geo::extract_track_from_gpx(res.src_gpx)
      #res.src_len = Geo::length(res.src_track)
    rescue Exception => e
      puts "exception: " + e.to_s
    end
    res
  end

  def ajax_param(params)
    res = ""
    url_info = params.src_url_object
    res += "=&End="
    res += url_info.end.lon.to_s
    res += "%2C"
    res += url_info.end.lat.to_s
    res += "&Start="
    res += url_info.start.lon.to_s
    res += "%2C"
    res += url_info.start.lat.to_s
    if url_info.via
      res += "&Via="
      via_res = ""
      url_info.via.each {|via|
        #<xls:ViaPoint><xls:Position><gml:Point><gml:pos>8.3881509 49.0268442</gml:pos></gml:Point></xls:Position></xls:ViaPoint>
        via_res += "<xls:ViaPoint><xls:Position><gml:Point><gml:pos>#{via.lon} #{via.lat}</gml:pos></gml:Point></xls:Position></xls:ViaPoint>"
      }
    end
    res += CGI::escape(via_res)
    # &_=&avoidAreas=&distunit=KM&instructions=true&lang=en&noMotorways=false&noTollways=false&routepref=Pedestrian&useTMC=
    res += "&_=&avoidAreas=&distunit=KM&instructions=false&lang=en&noMotorways=true&noTollways=false&routepref=Pedestrian&useTMC="
    res
  end

  def smoothen(params)
    track = params.src_track
    @newvia = params.src_url_object.via.map { |el|
      ix = track.index(el)
      if not ix
        el
      else
        a = (ix == 0 ? nil : track[ix-1])
        e = (ix < track.count()-1 ? track[ix+1] : nil)
        res = (a and e ? Geo::Coordinate.new((a.lat + e.lat)/2, (a.lon + e.lon)/2) : el)
        track[ix] = res
        res
      end
    }
    # dst_track = Geo::map_track_to_gpx params.src_track
    # xml = XmlSimple.xml_in(params.src_gpx)
    # xml['trk'][0]['trkseg'][0]['trkpt'] = dst_track
    wpt_track = Geo::calc_fixed_distance_points(params.src_track,params.distance)
    #wpts = Geo::map_track_to_gpx wpt_track
    #(0...wpts.length).each {|ix|
    #  wpts[ix]['name'] = (ix+1).to_s + 'km'
    #}
    # xml['wpt'] =wpts
    params.res_gpx = Geo::create_kml(params.src_track, wpt_track) # XmlSimple.xml_out(xml,'rootname' => 'gpx') if params.smooth
    params.res_len = Geo::length(track)
  end

  def log(s)

    f = File.new(File.dirname(__FILE__) +"/log.txt","a+")
    f.write(s)
    f.write("\n")
    f.close
  end


  def do_routing(param)
    return if not param.src_url_object
    require 'httptester'
    http_params = HttpParams.new
    http_params.protocol = 'HTTP'
    http_params.host = 'openrouteservice.org'
    http_params.port = 80
    http_params.path = "/php/OpenLSRS_DetermineRoute.php"
    http_params.send_header = "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n
                               Accept-Encoding: gzip, deflate\r\n
                               Accept-Language: en-us,en;q=0.5\r\n
                               X-Prototype-Version: OpenLayers\r\n
                               X-Requested-With: XMLHttpRequest\r\n"
    # example
    # http_params.params = "=&End=8.3876235%2C49.0264548&Start=8.3866078%2C49.0263935&Via=%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3881509%2049.0268442%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3883960%2049.0295360%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3887243%2049.0313999%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3817870%2049.0353322%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3782894%2049.0358105%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3772809%2049.0372735%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3772720%2049.0381816%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3772037%2049.0412707%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3649595%2049.0497292%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3571128%2049.0542035%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3593982%2049.0515077%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3679000%2049.0415772%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3700391%2049.0399647%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3718095%2049.0384877%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3751015%2049.0359935%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3763040%2049.0352370%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3765904%2049.0350477%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3763595%2049.0328271%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3758569%2049.0282347%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3754318%2049.0229758%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3752988%2049.0215212%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3816032%2049.0214359%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3830144%2049.0209760%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3855781%2049.0207264%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E%3Cxls%3AViaPoint%3E%3Cxls%3APosition%3E%3Cgml%3APoint%3E%3Cgml%3Apos%3E8.3867396%2049.0220456%3C%2Fgml%3Apos%3E%3C%2Fgml%3APoint%3E%3C%2Fxls%3APosition%3E%3C%2Fxls%3AViaPoint%3E&_=&avoidAreas=&distunit=KM&instructions=true&lang=en&noMotorways=false&noTollways=false&routepref=Pedestrian&useTMC="
    http_params.params = ajax_param(param)
    http_params.post = "post"
    new_params = HttpProcessor.new(http_params).process

    log "received body: " + new_params.recv_body
    param.src_track = Geo::extract_track_from_gml(new_params.recv_body)
    log "after extract track"
    param.src_len = Geo::length(param.src_track)
    log "after length: " + param.src_len.to_s
    param.src_gpx = Geo::create_src_gpx(param.src_track)
    log "after create src gox: " + param.src_len.to_s
  end


  def process(params)
    do_routing(params)
    if params.src_track
      log "before do smoothen"
      smoothen(params)
      log "after do smoothen"
      if params.correct_via
        log "before create_URL"
        res = create_URL(params)
        log "after create_URL"
        res
      end
    end
    params
  end

  def conv_route_cgi(cgi, params)
    cgi.html {
      cgi.head {
        cgi.title { "Some Conversion Tools" } +
            cgi.style('type' => "text/css") {
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
            cgi.h1 { "Convert Route" } +
                cgi.form('METHOD' => 'get', 'name' => "conversionform") {
                  cgi.table {
                    cgi.tr {
                      cgi.td { "Source Url" } +
                          cgi.td {
                            cgi.textarea('name' => 'srcurl', 'cols' => '100', 'rows' => '4') { params.src_url }
                          }
                    } +
                        #cgi.tr {
                        #  cgi.td { "Source GPX" } +
                        #      cgi.td {
                        #        cgi.textarea('name' => 'srcgpx', 'cols' => '100', 'rows' => '10') { params.src_gpx }
                        #      }
                        #} +
                        cgi.tr {
                          cgi.td { "---" } +
                              cgi.td {
                                cgi.p{"Distance:" +
                                    cgi.input('type' => 'text', 'name' => 'distance', 'value' => params.distance.to_s)
                                  # +
                                  #" Smooth:" +
                                  #cgi.input('type' => 'checkbox', 'name' => 'smooth', 'value' => "", "checked" => (params.smooth ? 'true' : nil))+
                                  #" Correct Vias:"+
                                  #cgi.input('type' => 'checkbox', 'name' => 'correct_via', 'value' => "", 'checked' => (params.correct_via ? 'true' : nil))
                                }
                              }
                        } +
                        cgi.tr {
                          cgi.td { "Infos" } +
                              cgi.td {
                                cgi.p{"Src-Length: " + (params.src_len ? params.src_len.round.to_s : 0).to_s + "m Smoothened-Length: " + (params.res_len ? params.res_len.round.to_s : 0).to_s + "m"}
                              }
                        } +
                        cgi.tr {
                          cgi.td {
                            cgi.input('type' => "submit", 'name' => "process", 'value' => "convert") +
                            cgi.input('type' => "submit", 'name' => "kml", 'value' => "kml")
                          }
                        }
                    }
                  } +
                cgi.form('name' => "resultform") {
                    cgi.table {
                        cgi.tr {
                          cgi.td { "Result Url" } +
                              cgi.td {
                                cgi.textarea('name' => 'resurl', 'cols' => '100', 'rows' => '4') { params.res_url }
                              }
                        } +
                        cgi.tr {
                          cgi.td { "Result GPX" } +
                              cgi.td {
                                cgi.textarea('name' => 'resgpx', 'cols' => '100', 'rows' => '10') { params.res_gpx }
                              }
                        }
                  }
                }
          }
    }
  end

# @param [Object] cgi
# @param [Object] params
  def kml(cgi, params, path)
    cgi.html {
      cgi.head {
        #'<meta name="viewport" content="initial-scale=1.0, user-scalable=no" />\n'
        #+ '<meta http-equiv="content-type" content="text/html; charset=UTF-8"/>\n'
        cgi.meta('name' => 'viewport', 'content' => 'initial-scale=1.0, user-scalable=no') +
        cgi.title {'Google Maps JavaScript API v3 Example: Map Layers'} +
        cgi.meta('http-equiv' => 'content-type', 'content' => 'text/html; charset=UTF-8') +
        cgi.script('type' => 'text/javascript', 'src' => 'http://maps.google.com/maps/api/js?sensor=false') +
        cgi.script('type' => 'text/javascript') {
          %Q{ var map;

              var kmlLayer = null;
              var currentLayer = null;

              function initialize() {
                var myLatlng = new google.maps.LatLng(37.42166, -119.272);
                var myOptions = {
                  zoom: 5,
                  center: myLatlng,
                  mapTypeId: google.maps.MapTypeId.ROADMAP
                }
                map = new google.maps.Map(document.getElementById("map_canvas"), myOptions);

                kml();
              }

              function kml() {
                url = document.getElementById("kmlUrl").value;
                clearLayer();
                kmlLayer = new google.maps.KmlLayer(url, { map: map });
                currentLayer = kmlLayer;
              }

              function clearLayer() {
                if (currentLayer != null) {
                  currentLayer.setMap(null);
                }
              }

              function kmlKeyUp(e) {
                var keyCode;

                if (window.event) {
                    keyCode = window.event.keyCode;
                } else if (e) {
                    keyCode = e.which;
                }

                if (keyCode == 13) {
                    document.getElementById("kmlUrl").blur();
                    document.getElementById("kmlButton").click();
                }
              }
          }
        } +
        cgi.style {
          %Q{
            body {
              font-family: sans-serif;
            }

            #map_canvas {
              border: 1px solid black;
            }

            #layers {
              border: 1px solid #000088;
              background-color: #e0e0e0;
              width: 1024px;
              margin-top: 1px;
            }

            #heading {
              font-weight: bold;
              margin: 2px;
            }
          }
        }
      } +
      cgi.body('style'=>'margin:0px; padding:0px;', 'onload'=>'initialize()') {
        cgi.div('id'=>'map_canvas','style'=>'width:1024px; height:800px') +
        cgi.div('id' => 'layers') {
          cgi.div('id'=>'heading') {'Layers'} +
          cgi.table {
            cgi.tr {
              cgi.td {
                cgi.input('checked'=>nil,'onclick'=>'kml()','type'=>'radio','name'=>'layer','id'=>'kmlButton','value'=>'kml')
              } +
              cgi.td('align'=>'left') {
                'KML:' +
                cgi.input('type'=>'text','size'=>'60','id'=>'kmlUrl','onkeyup'=>'kmlKeyUp(event)',
                          'value'=>@@test_mode ? 'http://aschoerk.de/tmp/short.kml' : 'http://aschoerk.de/tmp/' +path)
              }
            }
          }
        }
      }
    }
  end

  # require 'tempfile'
  def initCGI(cgi)
    cgi.out {
      params = interpret_params(cgi)
      puts "inputparams" + params.to_s
      params = process(params)
      if not params.kml
        log "before conv_route_cgi"
        res = conv_route_cgi(cgi, params)
        log "after conv_route_cgi"
        res
      else
        dirname = File.dirname(__FILE__)
        # f = Tempfile.open("kmlfile", dirname + "/..")
        # f.write params.src_gpx
        # f.close
        log "before writing kml"
        newname = dirname+"/../tmp/test.kml"
        f = File.open(newname,"w+")
        f.write params.res_gpx
        f.close
        log "after writing kml"
        # File.rename(f.path,newname)
        res = kml(cgi,params, "test.kml")
        log "after kml"
        res
      end
    }
    return cgi
  end
end

def initCGI (cgi)
  RouteConverter.new.initCGI(cgi)
end

if __FILE__ == $0
  @@test_mode = false
  cgi = CGI.new("html3")
  initCGI(cgi)
end

