require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  describe "user creation" do

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

      LdapModel.setup(
        :organisation => PuavoRest::Organisation.default_organisation_domain!,
        :rest_root => "http://" + CONFIG["default_organisation_domain"],
        :credentials => {
          :dn => PUAVO_ETC.ldap_dn,
          :password => PUAVO_ETC.ldap_password }
      )

      @user = PuavoRest::User.new(
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpw"
      )
      @user.save!

      @teaching_group = PuavoRest::Group.new(
        :name => "5A",
        :abbreviation => "gryffindor-5a",
        :type => "teaching group",
        :school_dn => @school.dn.to_s
      )
      @teaching_group.save!

      @year_class = PuavoRest::Group.new(
        :name => "5",
        :abbreviation => "gryffindor-5",
        :type => "year class",
        :school_dn => @school.dn.to_s
      )
      @year_class.save!

    end

    it "has Fixnum id" do
      # FIXME: should be String
      assert_equal Fixnum, @user.id.class
    end

    it "has dn" do
      assert @user.dn, "model got dn"
    end

    it "has email" do
      assert_equal @user.email, "heli.kopteri@example.com"
    end

    it "has home directory" do
      assert_equal "/home/heli", @user.home_directory
    end

    it "has gid_number from school" do
      assert_equal @school.gidNumber, @user.gid_number
    end

    it "has displayName ldap value" do
      assert_equal ["Heli Kopteri"], @user.get_raw(:displayName)
    end

    it "can be fetched by dn" do
      assert PuavoRest::User.by_dn!(@user.dn), "model can be found by dn"
    end

    it "has school" do
      assert_equal "Gryffindor", @user.schools.first.name
    end


    it "has internal samba attributes" do
      assert_equal ["[U]"], @user.get_raw(:sambaAcctFlags)

      samba_sid = @user.get_raw(:sambaSID)
      assert samba_sid
      assert samba_sid.first
      assert_equal "S", samba_sid.first.first

      samba_primary_group_sid = @user.get_raw(:sambaSID)
      assert samba_primary_group_sid
      assert samba_primary_group_sid.first
      assert_equal "S", samba_primary_group_sid.first.first

      samba_group = PuavoRest::SambaGroup.by_attr!(:name, "Domain Users")
      assert(
        samba_group.members.include?(@user.username),
        "Samba group 'Domain users' includes the username"
      )
    end

    it "can add secondary emails" do
      @user.secondary_emails = ["heli.another@example.com"]
      @user.save!

      assert_equal @user.email, "heli.kopteri@example.com"
      assert_equal @user.secondary_emails, ["heli.another@example.com"]

      user = PuavoRest::User.by_dn!(@user.dn)
      assert_equal user.email, "heli.kopteri@example.com"
      assert_equal user.secondary_emails, ["heli.another@example.com"]
    end

    it "can change primary email without affecting secondary emails" do
      @user.secondary_emails = ["heli.another@example.com"]
      @user.save!

      @user.email = "newemail@example.com"
      @user.save!

      assert_equal @user.email, "newemail@example.com"
      assert_equal @user.secondary_emails, ["heli.another@example.com"]

      user = PuavoRest::User.by_dn!(@user.dn)
      assert_equal user.email, "newemail@example.com"
      assert_equal user.secondary_emails, ["heli.another@example.com"]
    end

    it "can authenticate using the username and password" do
      basic_authorize "heli", "userpw"
      get "/v3/whoami"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal "heli", data["username"]
    end

    it "can change the password" do
      user = PuavoRest::User.by_dn!(@user.dn)
      user.password = "newpw"
      user.save!

      basic_authorize "heli", "userpw"
      get "/v3/whoami"
      assert_equal 401, last_response.status, "old password is rejected"

      basic_authorize "heli", "newpw"
      get "/v3/whoami"
      assert_200
    end

    it "does not break active ldap" do
      user = User.new(
        :givenName => "Mark",
        :sn  => "Hamil",
        :uid => "mark",
        :puavoEduPersonAffiliation => "student",
        :puavoLocale => "en_US.UTF-8",
        :mail => ["mark@example.com"],
        :role_ids => [@role.puavoId]
      )

      user.set_password "secret"
      user.puavoSchool = @school.dn
      user.role_ids = [
        Role.find(:first, {
          :attribute => "displayName",
          :value => "Maintenance"
        }).puavoId,
        @role.puavoId
      ]
      user.save!

    end

    it "can add and remove groups" do
      @user.teaching_group = @teaching_group
      @user.year_class = @year_class

      assert @teaching_group.member_dns.include?(@user.dn), "User is not group member"
      assert_equal @user.teaching_group.name, "5A"

      assert @year_class.member_dns.include?(@user.dn), "User is not group member"
      assert_equal @user.year_class.name, "5"

      @user.teaching_group = nil
      @teaching_group = PuavoRest::Group.by_id(@teaching_group.id) # FIXME? why should be reload from ldap?
      assert !@teaching_group.member_dns.include?(@user.dn), "User is group member"
      assert_nil @user.teaching_group

    end

    it "cannot have duplicate external IDs" do
      @donald = PuavoRest::User.new(
        :first_name => "Donald",
        :last_name => "Duck",
        :username => "donald.duck",
        :school_dns => [@school.dn.to_s],
        :roles => ["student"],
        :external_id => "donald")

      assert @donald.save!

      # This will fail because we're reusing Donald's external ID
      @daisy = PuavoRest::User.new(
        :first_name => "Daisy",
        :last_name => "Duck",
        :username => "daisy.duck",
        :school_dns => [@school.dn.to_s],
        :roles => ["student"],
        :external_id => "donald"
      )

      exception = assert_raises ValidationError do
        assert @daisy.save!
      end

      # Who created this error message? Seriously.
      assert_equal("Creating\n  Invalid attributes for PuavoRest::User " +
                   ":\n    * external_id: external_id=donald is not unique\n\n",
                   exception.message)

      # Change the external ID and try again. Have to create a new object
      # because it's filled with LDAP junk during the insertion attempt.
      @daisy = PuavoRest::User.new(
        :first_name => "Daisy",
        :last_name => "Duck",
        :username => "daisy.duck",
        :school_dns => [@school.dn.to_s],
        :roles => ["student"],
        :external_id => "daisy"
      )

      assert @daisy.save!
    end
  end
end
