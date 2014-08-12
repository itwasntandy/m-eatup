#This is a simple app to try to find the best place for a group of friends to meet up and eat.
#Normally this would be broken down into a number of classes, but because I'm just sending a gist
#I've left the various methods in the one file and not broken them out.
#The app will take input in the form of a bunch of address[] parameters in a uri query string and 
#food type via the optional type parameter.
#It then calculates an appropriate midpoint through iterating through the inputted addresses
#and looking for the center of the great circle path where each pair intersect
#it then calls out to the Yelp! API to find suitable restaurants near there, and outputs that to the requester.
#To help with debugging and improving quality along the way it logs request parameters and results to a database.
#For now this is a MySQL DB, should there ever be more than just me using this, I'll rethink that decision.
#For now I've wrapped all DB queries in such a way that it is easy to disable it, and any failure with the DB during a request will cause logging ot be disabled
#for the rest of the request
#The other reason for logging the event into the DB, is I would like to use them to allow users to schedule event
#and have others sign up to them. This is a TBD.
#Something akin to Doodle, but taking it much further as the app would chose not only the best date, but also the best location, and a restaurant.
#If I were able to hook it up to the Google Maps Routing API, it could then send out directions to each person, and reminders prior to the event.
#Once all that is done, being able to hook up to the OpenTable API to book a table on the scheduled date for everyone who can make it, at the appropriate restaurant
#would be the icing on the cake.
#In the future it should deal with edge cases better - eg. the midpoint between london and paris is over the sea, so there is no restaurant close to the midpoint.
#Also in the future it would be good to hook up to a routing API, as the geographic midpoint may in some cases take longer to get to then going from point A to point B.
#and this will allow people to specify method of travel too.
#i.e. Andrew is happy to go by foot, car or public transport
#Will is happy to go by foot, bicyle or public transport
#Harry is happy to go by public transport, and walk no more than 10 minutes
require 'cgi'
require 'json'
require 'openssl'
require 'geokit'
require 'yelpster'
require 'uri'
require 'mysql2'
require 'yaml'

#Decided it would be a good idea to move the config variables out of the main app
#so this is done through reading a yaml file and creating a hash of hashes for this.
#Currently it needs the config file to be named config.yml and for it to be in the same
#directory as the running app.
#The config file needs to contain credentials for all the remote services used.
#You can sign up for a YELP developer account here: http://www.yelp.com/developers
#you can sign up for a MySQL db (from the free tier) with AWS: http://aws.amazon.com/rds/
# database:
#   host: "localhost"
#   user: "username"
#   passwd: "password"
#   dbname: "m_eatup"
# yelp:
#   ywsid: ""
#   consumer_key: ""
#   consumer_secret: ""
#   token: ""
#   token_secret: ""
# zulip:
#   username: ""
#   apikey: ""
#
class DBLogger
  attr_accessor :dbclient
  def initialize(config)
    @dbclient =  Mysql2::Client.new(:host => config["host"],
                                    :username => config["user"],
                                    :password => config["passwd"],
                                    :database => config["dbname"]
                                   )
  end
 
  #A number of simple methods to log various steps along the way to a database.
  #Right now I have 5 tables:
  #events (eventid INT AUTO_INCREMENT,request_time TIMESTAMP, foodtype VARCHAR(256))
  #addresses (addressid INT AUTO_INCREMENT, eventid INT,address VARCHAR(256))
  #address_coordinates (addresscoordid INT AUTO_INCREMENT,addressid INT ,coordinates VARCHAR(100))
  #midpoints (midpointid INT AUTO_INCREMENT, eventid INT, coordinates VARCHAR(100))
  #results (resultid INT AUTO_INCREMENT, eventid INT, result_name VARCHAR(100), result_address VARCHAR(256))
  #In terms of the naming of the methods for each request we have:
  #  1 event
  #  multiple addresses
  #  multiple address coordinates
  #  1 final midpoint
  #  1 result
  # That has determined how I named these methods.
  def event(food)
    dbclient.query("insert into events(foodtype) values (\'#{food['type']}\')") rescue nil
    dbclient.last_id rescue nil
  end
  def addresses(eventid,address)
    dbclient.query("insert into addresses(eventid,address) values(#{eventid},\'#{address}\')") rescue nil
    dbclient.last_id rescue nil
  end
  def address_coordinates(addressid,coordinates)
    dbclient.query("insert into address_coordinates (addressid,coordinates) values(#{addressid},\'#{coordinates}\')") rescue nil
    dbclient.last_id rescue nil
  end
  def midpoint(eventid,coordinates)
    dbclient.query("insert into midpoints (eventid,coordinates) values(#{eventid},\'#{coordinates}\')") rescue nil
    dbclient.last_id rescue nil
  end
  def result(eventid,results)
    dbclient.query("insert into results (eventid,result_name,result_address) value (#{eventid},\'#{results['name']}\',\'#{results['location']['display_address']}\')") rescue nil
    dbclient.last_id rescue nil
  end
end

class FoodFinder
   attr_accessor :yelp_client
   def initialize(config)
     Yelp.configure(:yws_id => config["ywsid"],
                    :consumer_key => config["consumer_key"],
                   :consumer_secret => config["consumer_secret"],
                    :token => config["token"],
                    :token_secret => config["token_secret"])  
     @yelp_client = Yelp::Client.new()
   end
  
  #two simple methods to convert from radians into degrees and vice versa
  def to_radians(n)
    r = n * (Math::PI / 180)
    return r
  end
  def to_degrees(n)
    d = n * (180 / Math::PI)
    return d
  end
  
  
  #Method to take in array of addresses (input_addresses) and transform them into
  #an array of coordinates in radian format, so that they can be used to find the midpoint later.
  #An input_address array containing
  # input_addresses =  ["co43sq", "ec1v4ex"]
  # would then become the addresses array containing:
  # addresses = [[0.9054167399564751, 0.016493853614195475], [0.8993943033488851, -0.0018665476045330916]]
  # Again this will log to databases along the way so as to enable debugging of any problems and 
  # enable the results to be used to improve future requests.
  def map_addresses(logger,eventid,input_addresses)
    input_addresses.map do |a| 
      addressid = logger.addresses(eventid,a)
      begin
        result = Geokit::Geocoders::GoogleGeocoder.geocode(a)
      rescue
        return "GeoError: Either there is a problem reaching Google maps or the input is invalid #{a}"
      end
      if ((result.lat).kind_of? Float ) && ((result.lng).kind_of? Float)
       logger.address_coordinates(addressid,[to_radians(result.lat),to_radians(result.lng)])
       [to_radians(result.lat), to_radians(result.lng)]
      else
        return "Validation Error: #{a} is not a valid address input."
      end
    end
  end
  
  # Find the midpoint between two coordinates.
  # addr1 and addr2 are arrays in the format of [latitude,longitude], as that seems to be the normal convention.
  # this is actually finding the midpoint of the great circle that addr1 and addr2 live on.
  # my maths was rusty, as its 14 years since I quit my UG degree, so I was prompted by
  # http://mathforum.org/library/drmath/view/51822.html
  # to help with the formula.
  # it requires coordinates to be expressed in radians.
  def find_midpoint(addr1,addr2)
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
  
  # Sometimes just searching for the inputted string will not return the answers we want, so it becomes necessary to refine the string
  # Long term this will probably be enhanced to use the category list from yelp as a basis:
  # http://www.yelp.co.uk/developers/documentation/category_list
  #That said Yelp's category filter seems a little unreliable in testing, so a TBD to improve upon that.
  #I've found in testing that sometimes searching or what you think is a simple enough request (e.g. french restaurant in paris, or thai restauraunt
  #in rome, that you can end up getting unpredictable results
  #For example with category "restaurants" or "restaurants,french" that you would get back quite useless results e.g. 
  #/lookup?address[]=75011,Paris&address[]=75004,Paris&type=french would return
  # a link to the Place Des Voges park.
  # By experimenting it has been discovered that overriding this with the string "french restaurant" as the term delivers the correct result.
  # similarly searching for "thai" in rome, returns by default a massage palour. Augumenting thestring with restaurant again helps here.
  def refine_food(food)  
    case food["type"]
    when /thai/i
      food["category"] << "thai"
      food["type"] = "thai restaurant"
    when /indian|curry/i
      food["category"] << "indpak"
    when /french|france/i
      food["category"] << "french"
      food["type"] ="french restaurant"
    when /ital(ian|y)/i
      food["category"] << "italian"
      food["type"] = "italian restaurant"
     when /fish|seafood/i
      if (food["type"] =~ /chips/i)
        then food["category"] << "fishnchips"
        else
          food["category"] << "seafood"
          food["type"] = "fish restaurant"
      end
    end
    return food
  end
  
  
#  log = DBLogger.new(config["database"])
  
  #error { @error = request.env['sinatra_error'] ; haml :'500' }
  
  #example URL:
  #http://localhost:4567/lookup?address[]=ec1v4ex&address[]=co43sq&address[]=wc1b5ha&type=thai#env-info
  def lookup(content, logger)
      #puts content
      split_content = []
      split_content = content.split(',')
      
      if split_content.length <= 1
          address = "455 Broadway New York"
          split_content = [content, address]
      elsif split_content.length > 10 
          return "More than 10 input parameters detected.. this could prove expensive. aborting"
      end

  
    #if food type is specified, then use it, otherwise, set the term to restaurant and rely on yelp
    #make a good choice!
    #Try to improve the search terms by referencing the refine_food method which has tweaks for various search terms
    #which have shown in testing to not work as expected.
    food = Hash.new
    food["category"] = "[restaurants]"
    #if params.has_key?("type")
    #  food["type"] = params.fetch("type")
      food["type"] = split_content[0] 
      food = refine_food(food)
  
    #eventid = 0
    eventid = logger.event(food)
    #create an array containing all the addresses inputted
    #n.b. when making a query manually you need to pass parameters in the form of:
    #address[]=ec1v4ex&address[]=co43sq .. because otherwise sinatra creates a string named address
    #rather than an array
 #   if params.has_key?("address")
    input_addresses = []
    length = split_content.length-1
    for i in 1..length do
      input_addresses[i-1] = split_content[i]
    end
   
    #STDOUT.writeln input_addresses.length
    # if we don't have at least two addresses, we should fail, as how can we find a midpoint with only one place.
    # Create an addresses array from the input_addresses array by converting the postcodes or addresses into coordinates in the form of radians.
    # we call the map_addresses method defined above to do this.
    addresses = map_addresses(logger,eventid,input_addresses)
    # manipulate the addresses array again, this time to get the coordinates sorted.
    #STDOUT.write addresses
    if addresses.length <2
        #if only have one address, don't bother trying to find a midpoint
        midpoints=addresses
    else
    
      sorted_addresses = addresses.sort
      # create the midpoints array based on an initial looping through the addresses array to find the midpoints there 
      # midpoints is a nested array like addresses became above.
      midpoints = loop_midpoints(sorted_addresses)
  
      # if the length of the midpoint array is already 1, due to only 2 addresses being passed the below will be skipped
      # Otherwise keep iterating through the midpoints, until there is 1.
      # Again we want to log the output from this to help in debugging in the event of strange results
      while midpoints.length > 1 do
        addr = midpoints.sort!
        midpoints = loop_midpoints(addr)
      end
      logger.midpoint(eventid,midpoints[0])
  
    end
        # call out to Yelp using the yelpster gem to find a restaurant of the right type close to our midpoint
      # we call midpoints[0] because that's the first (and only remaining) element int he midpoint array
      # and pass the lat and long in accordingly.
      # we specify limit of 1, as we just want the first returned restaurant for now
      # we specify sort type of 1 which is to find the closest (recommended) one to our location
      # This because we specify a wide search radius to deal with cases where the midpoint may be a little away
      # from the nearest civilization!
      # This is wrapped into a begin/rescue statement, to cope with cases where the YELP API is unavailable
    #
    begin
      request = Yelp::V2::Search::Request::GeoPoint.new(
                :term => food["type"],
                :latitude => to_degrees(midpoints[0][0]),
                :longitude => to_degrees(midpoints[0][1]),
                :limit => 10,
                :radius =>40000,
                :sort => 1,
                :category => food["category"]
                 )

    response = yelp_client.search(request)
    rescue
      return "YelpError: YELP API is unavailable right now."
    end
  
    #finally we output the search results if we have the,
    #For now we are just outputting the yelp json verbatim as it contains all the useful information
    #We catch the case if the search doesn't return any result.
    #Again we log the put from this, so we can analyze it later.
    if response.has_key?('businesses')
      #[response.fetch('businesses')[0]('name'), response.fetch('businesses')[0]('display_address')].join(' ')
      random_seed = Random.new
      max_val = response.fetch('businesses').length - 1
      seed = random_seed.rand(0..max_val)

      logger.result(eventid,response['businesses'][seed])
      cultivated_response = [response.fetch('businesses')[seed]['name'], response.fetch('businesses')[seed]['location']['display_address']].join(', ')
      cultivated_response = [cultivated_response, response.fetch('businesses')[seed]['rating_img_url']].join('  ')
      return cultivated_response
    else
      return "Search Error: No results found near your midpoint which was determined to be #{to_degrees(midpoints[0][0])}, #{to_degrees(midpoints[0][1])}"
    end
  end
end
