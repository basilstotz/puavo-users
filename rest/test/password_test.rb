require_relative "./helper"

describe PuavoRest::Password do

  before(:each) do
    Puavo::Test.clean_up_ldap

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoSchoolHomePageURL => "schoolhomepage.example"
    )

    @group = Group.new
    @group.cn = "group1"
    @group.displayName = "Group 1"
    @group.puavoSchool = @school.dn
    @group.save!

    @role = Role.new
    @role.displayName = "Some role"
    @role.puavoSchool = @school.dn
    @role.groups << @group
    @role.save!

    @student = User.new(
      :givenName => "Bob",
      :sn  => "Brown",
      :uid => "bob",
      :puavoEduPersonAffiliation => "student",
      :mail => "bob@example.com",
      :role_ids => [@role.puavoId]
    )

    @student.set_password "secret"
    @student.puavoSchool = @school.dn
    @student.role_ids = [
      Role.find(:first, {
        :attribute => "displayName",
        :value => "Maintenance"
      }).puavoId,
      @role.puavoId
    ]
    @student.save!

    @teacher = User.new(
      :givenName => "Test",
      :sn  => "Teacher",
      :uid => "teacher",
      :puavoEduPersonAffiliation => "teacher",
      :mail => "teacher@example.com",
      :role_ids => [@role.puavoId]
    )

    @teacher.set_password "foobar"
    @teacher.puavoSchool = @school.dn
    @teacher.role_ids = [
      Role.find(:first, {
        :attribute => "displayName",
        :value => "Maintenance"
      }).puavoId,
      @role.puavoId
    ]
    @teacher.save!
  end

  describe "Test the school users list" do
    it "A student cannot view the school users list" do
      basic_authorize "bob", "secret"
      get "/v3/my_school_users"
      assert_equal 401, last_response.status
    end

    it "A teacher can view the school users list" do
      basic_authorize "teacher", "foobar"
      get "/v3/my_school_users"
      assert_equal 200, last_response.status
    end

    it "Ensure Bob Brown is listed on the page" do
      basic_authorize "teacher", "foobar"
      get "/v3/my_school_users"
      assert_equal 200, last_response.status

      # There's only one student, so this works... kinda
      # (If there were two students, there'd be 8 TD elements in the array)
      parts = parse_html(last_response.body).css(".users td")
      assert_equal 4, parts.length
      assert_equal "Brown", parts[0].content
      assert_equal "Bob", parts[1].content
      assert_equal "bob", parts[2].content
    end

    it "Ensure the group is listed" do
      basic_authorize "teacher", "foobar"
      get "/v3/my_school_users"
      assert_equal 200, last_response.status

      # Again there's only one group
      parts = parse_html(last_response.body).css("div#groupsList h1")

      assert_equal 1, parts.length
      assert_equal "Ungrouped", parts[0].content
    end
  end

  describe "Mailer class" do
    it "initialize and correct options" do
      email = PuavoRest::Mailer.new
      assert_equal({ :via => :smtp,
                     :from => "Opinsys <no-reply@opinsys.fi>",
                     :via_options => {
                       :address => CONFIG["password_management"]["smtp"]["via_options"][:address],
                       :port => 25,
                       :enable_starttls_auto => false
                     }
                   },
                   email.options )


    end

  end

  describe "POST /password/send_token" do
    it "send email message to user with url for reseting password" do
      $mailer = Class.new do
        def self.options
          return @options
        end

        def self.send(args)
          @options = args
        end
      end

      post "/password/send_token", {
        "username" => "bob"
      }
      assert_200

      data = JSON.parse(last_response.body)
      assert_equal "successfully", data["status"]

      jwt = $mailer.options[:body].match("https://example.opinsys.net/users/password/(.+)/reset$")[1]
      jwt_decode_data = JWT.decode(jwt, "foobar")
      jwt_data = jwt_decode_data[0] # jwt_decode_data is [payload, header]

      assert_equal "bob@example.com", $mailer.options[:to]
      assert_equal "Reset your password", $mailer.options[:subject]
      assert_equal "bob", jwt_data["username"]
      assert_equal "example.opinsys.net", jwt_data["organisation_domain"]
    end
  end

end
