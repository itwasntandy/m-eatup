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

def find_midpoint(lat1,long1,lat2,long2)
  dlong = long2 - long1
  
  bx = Math.cos(lat2) * Math.cos(dlong)
  by = Math.cos(lat2) * Math.sin(dlong)
 
  latmid = to_degrees(Math.atan2((Math.sin(lat1) + Math.sin(lat2)), Math.sqrt(( Math.cos(lat1)+bx)**2 + by**2)))
  longmid = to_degrees(long1 + Math.atan2(by, Math.cos(lat1) + bx))
  return [latmid, longmid]
end

get '/lookup' do
  content_type :json
  addresses = params.fetch("address")
  if addresses.length < 2
    "Error: not enough addresses sent"
  end
  addresses.map! {|a| Geokit::Geocoders::GoogleGeocoder.geocode(a)}
  
  #set a default foodtype to indian
  foodtype = "indian"
  foodtype = params.fetch("type")

  lat1 = to_radians(addresses[0].lat)
  lat2 = to_radians(addresses[1].lat)
  long1 = to_radians(addresses[0].lng)
  long2 = to_radians(addresses[1].lng)

  midpoint = find_midpoint(lat1,long1,lat2,long2)
  
  client = Yelp::Client.new
  request = Yelp::V2::Search::Request::GeoPoint.new(
              :term => foodtype,
              :latitude => midpoint[0],
              :longitude => midpoint[1],
              :limit => 1,
              :category => "food"
               )
 
  response = client.search(request)
  "the best restaurant to go to is #{response.fetch("businesses")[0].fetch("name")} and its address is #{response.fetch("businesses")[0].                 fetch("location").fetch("address")[0]}  #{response.fetch("businesses")[0].fetch("location").fetch("postal_code")}"

end
