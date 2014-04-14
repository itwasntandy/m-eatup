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

def find_midpoint(a1,a2)
  dlong = a2[1] - a1[1]
  
  bx = Math.cos(a2[0]) * Math.cos(dlong)
  by = Math.cos(a2[0]) * Math.sin(dlong)
 
  latmid = Math.atan2((Math.sin(a1[0]) + Math.sin(a2[0])), Math.sqrt(( Math.cos(a1[0])+bx)**2 + by**2))
  longmid = a1[1] + Math.atan2(by, Math.cos(a1[0]) + bx)
  return [latmid, longmid]
end

get '/lookup' do
  content_type :json
  addresses = params.fetch("address")
  if addresses.length < 2
    "Error: not enough addresses sent"
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
  
  0.upto(addresses.length - 2) do |index|
    a1 = addresses[index]
    a2 = addresses[index + 1]
    midpoints << find_midpoint(a1, a2)
  end 
 
  while midpoints.length != 1 do
    a = midpoints.sort
    midpoints = []
    0.upto(a.length - 2 ) do |index|
      a1 = a[index]
      a2 = a[index + 1]
      midpoints << find_midpoint(a1, a2)
    end
  end
      

  client = Yelp::Client.new
  request = Yelp::V2::Search::Request::GeoPoint.new(
              :term => foodtype,
              :latitude => to_degrees(midpoints[0][0]),
              :longitude => to_degrees(midpoints[0][1]),
              :limit => 1,
              :category => "food"
               )
 
  response = client.search(request)
  "the best restaurant to go to is #{response.fetch("businesses")[0].fetch("name")} and its address is #{response.fetch("businesses")[0].                 fetch("location").fetch("address")[0]}  #{response.fetch("businesses")[0].fetch("location").fetch("postal_code")}"

end
