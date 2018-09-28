
require_relative "./helper"

module School_test
describe PuavoRest::School do


  before(:each) do
    Timecop.travel(Fixtures::ICS_TIME)
    Puavo::Test.clean_up_ldap
    PuavoRest::Session.local_store.flushdb
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :preferredLanguage => "school-lang",
      :puavoSchoolHomePageURL => "gryffindor.example"
    )

    @school.external_feeds = "http://cal.example.com/cal.ics"
    @school.save!

    @school2 = School.create(
      :cn => "school2",
      :displayName => "School 2",
      :puavoSchoolCode => "0123450",
    )

    @school2.save!

    @server2 = create_server(
      :puavoHostname => "server2",
      :macAddress => "bc:5f:f4:56:59:72",
      :puavoDeviceType => "bootserver",
      :puavoSchool => @school.dn
    )
    PuavoRest.test_boot_server_dn = @server2.dn.to_s

    LdapModel.setup(
      :organisation =>
        PuavoRest::Organisation.default_organisation_domain!,
      :rest_root => "http://" + CONFIG["default_organisation_domain"],
                    :credentials => { :dn => PUAVO_ETC.ldap_dn, :password => PUAVO_ETC.ldap_password }
    )

  end

  after(:each) do
    Timecop.return
  end

  it "school codes are what they should be" do
    assert_nil PuavoRest::School.by_dn!(@school.dn).school_code
    assert_equal PuavoRest::School.by_dn!(@school2.dn).school_code, "0123450"
  end

  it "can change te school code for a school that does not have it yet" do
    school = PuavoRest::School.by_dn!(@school.dn)
    school.school_code = "foobar"
    school.save!
    assert_equal PuavoRest::School.by_dn!(@school.dn).school_code, "foobar"
  end

  it "can change te school code for a school that does have it already" do
    school = PuavoRest::School.by_dn!(@school2.dn)
    school.school_code = "bazquux"
    school.save!
    assert_equal PuavoRest::School.by_dn!(@school2.dn).school_code, "bazquux"
  end

  it "can clear the school code" do
    school = PuavoRest::School.by_dn!(@school.dn)
    school.school_code = nil
    school.save!
    school = PuavoRest::School.by_dn!(@school2.dn)
    school.school_code = nil
    school.save!
    assert_nil PuavoRest::School.by_dn!(@school.dn).school_code
    assert_nil PuavoRest::School.by_dn!(@school2.dn).school_code
  end

  it "has external_feed_sources" do
    school = PuavoRest::School.by_dn!(@school.dn)
    assert school.external_feed_sources
    assert_equal(
      [
        {
          "type"=>"ical",
         "name"=>"Opinsys",
         "value"=>"http://cal.example.com/cal.ics"
        }
      ],
      school.external_feed_sources
    )
  end

  it "has empty message before caching" do
    school = PuavoRest::School.by_dn!(@school.dn)
    assert_equal([], school.messages)
  end

  it "has messages after cache is populated" do
    school = PuavoRest::School.by_dn!(@school.dn)

    stub_request(:get, "http://cal.example.com/cal.ics").
      to_return(:body => File.new(Fixtures::ICS_FILE), :status => 200)

    school.cache_feeds()

    assert_equal(2, school.messages.size, school.messages)
    assert_equal "long event", school.messages[0]["message"]
    assert_equal "Gryffindor", school.messages[0]["to"]["name"]
    assert_equal "PuavoRest::School", school.messages[0]["to"]["object_model"]

    assert_equal "event of today", school.messages[1]["message"]
    assert_equal "Gryffindor", school.messages[1]["to"]["name"]
    assert_equal "PuavoRest::School", school.messages[1]["to"]["object_model"]
  end

  it "bad url does not interfere" do
    @school.external_feeds = ["http://cal.example.com/cal.ics", "bad"]
    @school.save!

    school = PuavoRest::School.by_dn!(@school.dn)

    stub_request(:get, "http://cal.example.com/cal.ics").
      to_return(:body => File.new(Fixtures::ICS_FILE), :status => 200)

    school.cache_feeds()

    assert_equal(2, school.messages.size, school.messages)
    assert_equal "long event", school.messages[0]["message"]
    assert_equal "Gryffindor", school.messages[0]["to"]["name"]
    assert_equal "PuavoRest::School", school.messages[0]["to"]["object_model"]

    assert_equal "event of today", school.messages[1]["message"]
    assert_equal "Gryffindor", school.messages[1]["to"]["name"]
    assert_equal "PuavoRest::School", school.messages[1]["to"]["object_model"]
  end

end
end
