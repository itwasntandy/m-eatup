require 'mysql2'
require 'yaml'

# DB logger class requires some parameters to be passed in.
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
