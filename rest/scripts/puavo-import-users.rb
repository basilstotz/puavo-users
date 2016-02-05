#!/usr/bin/ruby1.9.1
# -*- coding: utf-8 -*-

require 'optparse'
require 'csv'
require "elasticsearch"

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

include PuavoImport::Helpers

def last_login(domain, username)

  if @options[:es_url].nil?
    return "Can't get lastlogin"
  end

  if @es_client.nil?
    @es_client = Elasticsearch::Client.new(:url => @options[:es_url])
  end

  timestamp = nil
  today = Date.today
  indices = (1..180).map do |i|
    (today - i).strftime("fluentd-puavo-rest-%Y.%m.%d")
  end

  indices.each do |indice|
    begin
      query = "msg: \"created session\" AND created\\ session.session.organisation: \"#{ domain }\" AND created\\ session.session.user.username: \"#{ username }\""
      res = @es_client.search({
                          :ignore_unavailable => true,
                          :index => Array(indice),
                          :body => {
                            :_source => true,
                            :sort =>  { "@timestamp" => { :order => "asc" }},
                            :query => {
                              :filtered => {
                                :query => {
                                  :query_string => {
                                    :analyze_wildcard => true,
                                    :query => query
                                  }
                                }
                              }
                            }
                          }
                        })
      if res["hits"]["total"] > 0
        timestamp = res["hits"]["hits"][0]["_source"]["@timestamp"]
        break
      end

    rescue Elasticsearch::Transport::Transport::Errors::NotFound => err
      STDERR.puts err.to_s
      STDERR.puts
      STDERR.puts "Cannot find login timestamp"
    end

  end

  return timestamp

end

def update_user_groups(puavo_rest_user, user)
  case @options[:user_role]
  when "student"
    puavo_rest_user.teaching_group = user.teaching_group
    if user.year_class != user.teaching_group
      # FIXME: create year class if it not found?
      # FIXME: add user to yeah class
      #puavo_rest_user.year_class = user.year_class
    end
  when "teacher"
    puavo_rest_user.add_administrative_group(user.teacher_group)
  end
end

def update_puavo_rest_user_attributes(puavo_rest_user, user, attributes)
  attributes.each do |attribute|
    puavo_rest_user.send("#{ attribute }=", user.send(attribute.to_s))
  end
end

@options = PuavoImport.cmd_options(:message => "Import users to Puavo") do |opts, options|
  opts.on("--user-role ROLE", "Role of user (student/teacher)") do |r|
    options[:user_role] = r
  end

  opts.on("--teacher-group-suffix GROUP", "Group suffix for Teacher") do |g|
    options[:teacher_group_suffix] = g
  end

  opts.on("--matches x,y,x", Array) do |matches|
    options[:matches] = matches
  end

  opts.on("--not-skip-duplicate-user", "Handle duplicate puavo users") do |not_skip_duplicate_user|
    options[:not_skip_duplicate_user] = not_skip_duplicate_user
  end

  opts.on("--es-url ES_URL", "URL for Elasticsearch") do |es_url|
    options[:es_url] = es_url
  end
end

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

setup_connection(@options)

users = []

invalid_school = 0
invalid_group = 0
user_not_found_by_name = 0
found_many_users_by_name = 0
correct_csv_users = 0
update_external_id = 0
not_update_external_id = 0

CSV.foreach(@options[:csv_file], :encoding => @options[:encoding], :col_sep => ";" ) do |row|
  user_data = encode_text(row, @options[:encoding])

  user_data_hash = {
    :db_id => user_data[0],
    :external_id => user_data[1],
    :first_name => user_data[2],
    :given_names => user_data[3],
    :last_name => user_data[4],
    :email => user_data[5],
    :telephone_number => user_data[6],
    :preferred_language => user_data[7],
    :username => user_data[9],
    :role => @options[:user_role]
  }

  if @options[:user_role] == "student"
    user_data_hash.merge!({
      :school_external_id => user_data[8],
      :teaching_group_external_id => user_data[10],
      :year_class => user_data[11]
    })
  end

  if @options[:user_role] == "teacher"
    user_data_hash.merge!({
      :school_external_id => user_data[10],
      :teacher_group_suffix => @options[:teacher_group_suffix],
      :secodary_school_external_ids => user_data[8].nil? ? [] : Array(user_data[8].split(","))
    })
  end

  next if !@options[:include_schools].include?(user_data_hash[:school_external_id].to_s)

  begin
    user = PuavoImport::User.new(user_data_hash)
  rescue PuavoImport::UserGroupError => e
    puts e.to_s
    invalid_group += 1
    next
  end
  if user.school.nil?
    puts "Cannot find school (#{ user.school_external_ids }) for user: #{ user }"
    invalid_school += 1
    next
  end

  correct_csv_users += 1
  users.push(user)

end

mode = @options[:mode]

case mode
when "set-external-id"

  users.each do |user|

    if PuavoRest::User.by_attr(:external_id, user.external_id)
      next
    end

    puts "\n" + "-" * 100 + "\n\n"

    puavo_users = PuavoRest::User.by_attrs({ :first_name => user.first_name,
                                             :last_name => user.last_name,
                                             :roles => @options[:user_role]},
                                           { :multiple => true } )

    if puavo_users.empty?
      user_not_found_by_name += 1
      log_to_file("user_not_found_by_name")[:file].puts(user.to_s)
      next
    end

    puavo_user = puavo_users.first

    if puavo_users.length > 1
      found_many_users_by_name += 1
      log_to_file("found_many_users_by_name")[:file].puts user.to_s
      user_count = 0

      next unless @options[:not_skip_duplicate_user]

      puts "\nImport user:"
      puts "first name: #{ user.first_name }"
      puts "given names: #{ user.given_names }"
      puts "last_name: #{ user.last_name }"
      puts "school: " + user.import_school_name
      puts "group: #{ user.import_group_name }"
      puts

      puavo_users.each do |u|
        timestamp = last_login(@options[:organisation_domain], u.username)
        groups = u.groups.map{ |g| "'#{ g.name}'" }.join(", ")
        puts "#{ user_count } #{ u.first_name } #{ u.last_name }, #{ u.username }, #{ u.school.name }, #{ u.import_group_name }, last login (last 6 months): #{ timestamp }"
        user_count += 1
      end

      while(true) do
        response = ask("Choose the right user")

        number = response.to_i

        if puavo_users[number]
          puavo_user = puavo_users[number]
          break
        end
      end

    end

    different_attributes = diff_objects(puavo_user, user, ["first_name",
                                                           "last_name",
                                                           "import_school_name",
                                                           "import_group_name",
                                                           "external_id"] )

    response = "Y"

    if user.import_school_name != puavo_user.import_school_name
      response = "N"
    end

    if user.import_group_name.to_i != puavo_user.import_group_name.to_i
      response = "N"
    end

    #response = ask("Update external_id (#{ user.external_id }) to Puavo (Y/N)?",
    #               :default => "N")

    if response == "N"
      not_update_external_id += 1
      log_to_file("not_update_external_id")[:file].puts user.to_s
      next
    end

    puts "Update external id"
    puavo_user.external_id = user.external_id
    # puavo_user.external_data = FIXME
    puavo_user.save!
    update_external_id += 1

  end

  puts "correct_csv_users: #{ correct_csv_users }"
  puts "invalid_school: #{ invalid_school }"
  puts "invalid_group: #{ invalid_group }"
  puts "user_not_found_by_name: #{ user_not_found_by_name } file: #{ log_to_file("user_not_found_by_name")[:filename] }"
  puts "found_many_users_by_name: #{ found_many_users_by_name } file: #{ log_to_file("found_many_users_by_name")[:filename] }"
  puts "update_external_id: #{ update_external_id }"
  puts "not_update_external_id: #{ not_update_external_id } file: #{ log_to_file("not_update_external_id")[:filename] }"

when "diff"
  puts "Diff users\n\n"
  PuavoImport::User.all.each do |user|
    puavo_rest_user = PuavoRest::User.by_attr(:external_id, user.external_id)
    if puavo_rest_user
        different_attributes = diff_objects(puavo_rest_user, user, ["first_name",
                                                                    "last_name",
                                                                    "email",
                                                                    "telephone_number",
                                                                    "import_school_name",
                                                                    "import_group_name",
                                                                    "external_id"] )
    else
      puts "Can't find user: #{ user.to_s }"
    end

    puts "\n" + "-" * 100 + "\n\n"
  end

when "import"
  puts "Import users\n\n"
  PuavoImport::User.all.each do |user|
    puavo_rest_user = PuavoRest::User.by_attr(:external_id, user.external_id)
    if puavo_rest_user
      if user.need_update?(puavo_rest_user)
        puts "#{ puavo_rest_user["username"] }: update user information"

        update_attributes = [ :first_name,
                              :last_name,
                              :email,
                              :telephone_number ]

        update_attributes.delete(:email) if user.email.nil?

        update_puavo_rest_user_attributes(puavo_rest_user, user, update_attributes)

        # FIXME: We can not modify the role because admin user is able to add more roles for the user
        #puavo_rest_user.role = options[:user_role]
        #puavo_rest_user.username = user.username # FIXME invalid data?
        #puavo_rest_user.preferred_language = user.preferred_language FIXME: use school fallback?

        begin
          puavo_rest_user.validate!
        rescue ValidationError => validation_errors
          errors = validation_errors.as_json
          invalid_attributes = errors[:error][:meta][:invalid_attributes].keys
          invalid_attributes.each do |attribute|
            update_attributes.delete(attribute)
            puts "attribute: #{attribute}, value: '#{ user.send(attribute.to_s) }', error: " +
              errors[:error][:meta][:invalid_attributes][attribute].map { |a|
              a[:message]
            }.join(", ")
          end

          puavo_rest_user = PuavoRest::User.by_attr(:external_id, user.external_id)

          update_puavo_rest_user_attributes(puavo_rest_user, user, update_attributes)
        end

        puavo_rest_user.save!

        update_user_groups(puavo_rest_user, user)

      else
        puts "#{ puavo_rest_user["username"] }: no changes"
      end
    else
      puts "#{ user.to_s }: add user to Puavo"
      next
#      # FIXME Create password list for new users
#      # FIXME send email notifications to school admin
#      puavo_rest_user = PuavoRest::User.new(
#        :external_id => user.external_id,
#        :first_name => user.first_name,
#        :last_name => user.last_name,
#        :email => user.email,
#        :telephone_number => user.telephone_number,
#        :roles => [@options[:user_role]],
#        :school_dns => [user.school.dn.to_s],
#        # :preferred_language => user.preferred_language,
#        # :username => user.username,
#        )
#      puavo_rest_user.save!
#
#      update_user_groups(puavo_rest_user, user)

    end



  end
end
