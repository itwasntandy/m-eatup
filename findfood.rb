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


#two simple methods to convert from radians into degrees and vice versa

def to_radians(n)
  r = n * (Math::PI / 180)
  return r
end
  
def to_degrees(n)
  d = n * (180 / Math::PI)
  return d
end

def find_midpoint(addr1,addr2)
  # addr1 and addr2 are arrays in the format of [latitude,longitude], as that seems to be the normal convention.

  # this is actually finding the midpoint of the great circle that addr1 and addr2 live on.
  # my maths was rusty, as its 14 years since I quit my UG degree, so I was prompted by
  # http://mathforum.org/library/drmath/view/51822.html
  # to help with the formula.
  #
  # it requires coordinates to be expressed in radians.

  dlong = addr2[1] - addr1[1]
 

  bx = Math.cos(addr2[0]) * Math.cos(dlong)
  by = Math.cos(addr2[0]) * Math.sin(dlong)
 
  latmid = Math.atan2((Math.sin(addr1[0]) + Math.sin(addr2[0])), Math.sqrt(( Math.cos(addr1[0])+bx)**2 + by**2))
  longmid = addr1[1] + Math.atan2(by, Math.cos(addr1[0]) + bx)
  return [latmid, longmid]
end


# With N number of coordinates we want to be able to loop through them to get down to a final set of coordinates for midpoints
# the method below will take a set of coordinates in the form of an array, find the midpoints between the pairs.
# The effect is the array length returned is one shorter than the array length inputted.

def loop_midpoints(addr)
  midpoints = []
  0.upto(addr.length - 2 ) do | index|
    addr1 = addr[index]
    addr2 = addr[index + 1]
    midpoints << find_midpoint(addr1,addr2)
  end
  return midpoints
end


error { @error = request.env['sinatra_error'] ; haml :'500' }


#example URL:
#http://localhost:4567/lookup?address[]=ec1v4ex&address[]=co43sq&address[]=wc1b5ha&type=thai#env-info

get '/lookup' do
  content_type :json
  
  #create an array containing all the addresses inputted
  #n.b. when making a query manually you need to pass parameters in the form of:
  #address[]=ec1v4ex&address[]=co43sq .. because otherwise sinatra creates a string named address
  #rather than an array
  addresses = params.fetch("address")
  
  # if we don't have at least two addresses, we should fail, as how can we find a midpoint with only one place.
  if addresses.length < 2
    raise error, "Error: not enough addresses sent"
  end

  # manipulate the addresses array, to convert the postcodes or addresses into coordinates in the form of radians.
  # previously it might have  been:
  # addresses =  ["co43sq", "ec1v4ex"]
  #
  # afterwards it takes the form of a nested array expressed in the form of lat,long
  #
  # addresses = [[0.9054167399564751, 0.016493853614195475], [0.8993943033488851, -0.0018665476045330916]]
  addresses.map! do |a| 
    result = Geokit::Geocoders::GoogleGeocoder.geocode(a)
    [to_radians(result.lat), to_radians(result.lng)]
  end 

  # manipulate the addresses array again, this time to get the coordinates sorted.
  addresses.sort!

  #set a default foodtype to indian because its the most popular type of food in the uk
  #http://wiki.answers.com/Q/What_is_the_most_popular_dish_in_the_UK
  #
  #However override if if a type parameter is passed.
  foodtype = "indian"
  foodtype = params.fetch("type")

  # create the midpoints array based on an initial looping through the addresses array to find the midpoints there 
  # midpoints is actually an nested array, because 
  midpoints = loop_midpoints(addresses)

  # if the length of the midpoint array is already 1, due to only 2 addresses being passed the below will be skipped
  # Otherwise keep iterating through the midpoints, until it is 1.
  while midpoints.length > 1 do
    addr = midpoints.sort!
    midpoints = loop_midpoints(addr)
  end
      

   
  # call out to Yelp using the yelpster gem to find a restaurant of the right type close to our midpoint
  # we call midpoints[0] because that's the first (and only remaining) element int he midpoint array
  # and pass the lat and long in accordingly.
  # we specify limit of 1, as we just want the first returned restaurant for now
  # we specify sort type of 2, which says to return the highest rated
  # and we specify the category of restaurants, as we don't want take away joints
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
  #finally we output with some text.
  #this bit is still TBD, with some basic output given for debugging purposes
  "the best restaurant to go to is #{response.fetch("businesses")[0].fetch("name")} and its address is #{response.fetch("businesses")[0].                 fetch("location").fetch("address")[0]}  #{response.fetch("businesses")[0].fetch("location").fetch("postal_code")}"

end
