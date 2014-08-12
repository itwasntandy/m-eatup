m-eatup
=======


Determine the best place for you and your friends to meet


=====
** Instructions for use **

* Rename config-example.yml to config.yml
  * populate the config with settings for MySQL DB, Yelp API and Zulip API
* Run with ruby zulipbot.rb - currently it runs attached to the parent process, it doesn't daemonize
  * I've been running it in screen




* The other reason for logging the event into the DB, is I would like to use them to allow users to schedule event and have others sign up to them. This is a TBD.
   * Something akin to Doodle, but taking it much further as the app would chose not only the best date, but also the best location, and a restaurant.
* If I were able to hook it up to the Google Maps Routing API, it could then send out directions to each person, and reminders prior to the event.
* Once all that is done, being able to hook up to the OpenTable API to book a table on the scheduled date for everyone who can make it, at the appropriate restaurant would be the icing on the cake
* In the future it should deal with edge cases better - eg. the midpoint between london and paris is over the sea, so there is no restaurant close to the midpoint.
* Also in the future it would be good to hook up to a routing API, as the geographic midpoint may in some cases take longer to get to then going from point A to point B.  and this will allow people to specify method of travel too.
   * i.e. Andrew is happy to go by foot, car or public transport
   * Will is happy to go by foot, bicyle or public transport
   * Harry is happy to go by public transport, and walk no more than 10 minutes
