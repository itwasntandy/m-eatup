require 'sinatra'
require 'cgi'
require 'json'
require 'geokit'
require 'yelpster'
require 'uri'

YELP_YWSID = "***REMOVED***"
 
YELP_CONSUMER_KEY = "***REMOVED***"
YELP_CONSUMER_SECRET = "***REMOVED***"
YELP_TOKEN = "***REMOVED***"
YELP_TOKEN_SECRET = "***REMOVED***"
 
Yelp.configure(:yws_id => YELP_YWSID,
               :consumer_key => YELP_CONSUMER_KEY,
               :consumer_secret => YELP_CONSUMER_SECRET,
               :token => YELP_TOKEN,
               :token_secret => YELP_TOKEN_SECRET)

def to_radians(n)
  r = n * (Math::PI / 180)
  return r
end
  
def to_degrees(n)
  d = n * (180 / Math::PI)
  return d
end

def loop_midpoints(addr)
  midpoints = []
  0.upto(addr.length - 2 ) do | index|
    addr1 = addr[index]
    addr2 = addr[index + 1]
    midpoints << find_midpoint(addr1,addr2)
  end
  return midpoints
end

def find_midpoint(addr1,addr2)
  dlong = addr2[1] - addr1[1]
  
  bx = Math.cos(addr2[0]) * Math.cos(dlong)
  by = Math.cos(addr2[0]) * Math.sin(dlong)
 
  latmid = Math.atan2((Math.sin(addr1[0]) + Math.sin(addr2[0])), Math.sqrt(( Math.cos(addr1[0])+bx)**2 + by**2))
  longmid = addr1[1] + Math.atan2(by, Math.cos(addr1[0]) + bx)
  return [latmid, longmid]
end

error { @error = request.env['sinatra_error'] ; haml :'500' }

get '/lookup' do
  content_type :json
  addresses = params.fetch("address")
  if addresses.length < 2
    raise error, "Error: not enough addresses sent"
  end
  addresses.map! { |a| 
    result = Geokit::Geocoders::GoogleGeocoder.geocode(a)
    [to_radians(result.lat), to_radians(result.lng)]
  }
  addresses.sort!
  #set a default foodtype to indian
  foodtype = "indian"
  foodtype = params.fetch("type")

  midpoints = []
 
  midpoints = loop_midpoints(addresses)

 
  while midpoints.length > 1 do
    addr = midpoints.sort!
    midpoints = loop_midpoints(addr)
  end
      

  client = Yelp::Client.new
  request = Yelp::V2::Search::Request::GeoPoint.new(
              :term => foodtype,
              :latitude => to_degrees(midpoints[0][0]),
              :longitude => to_degrees(midpoints[0][1]),
              :limit => 1,
              :sort => 2,
              :category => "restaurants"
               )
 
  response = client.search(request)
  "the best restaurant to go to is #{response.fetch("businesses")[0].fetch("name")} and its address is #{response.fetch("businesses")[0].                 fetch("location").fetch("address")[0]}  #{response.fetch("businesses")[0].fetch("location").fetch("postal_code")}"

end
